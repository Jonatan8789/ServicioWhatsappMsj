const { setGlobalOptions } = require("firebase-functions");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler"); // 👈 Importamos onSchedule para v2
const logger = require("firebase-functions/logger");

setGlobalOptions({ maxInstances: 10 });

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const Afip = require('@afipsdk/afip.js');
const axios = require('axios');
const cheerio = require('cheerio');

if (!admin.apps.length) {
    admin.initializeApp();
}

// =========================================================================
// AUTORIZACIÓN: sólo usuarios con rol 'admin' en /usuarios/{uid} pueden
// operar los callables fiscales (AFIP/ARCA) y de cobro (Mercado Pago).
// Antes ninguno de estos onCall verificaba context.auth, así que cualquiera
// con la API key pública del proyecto podía invocarlos directo por HTTPS.
// =========================================================================
async function requireAdmin(context) {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Necesitás iniciar sesión para realizar esta operación.'
        );
    }
    const db = admin.firestore();
    const userDoc = await db.collection('usuarios').doc(context.auth.uid).get();
    const rol = userDoc.exists ? userDoc.data().rol : null;
    const activo = userDoc.exists ? (userDoc.data().activo ?? true) : false;
    if (rol !== 'admin' || !activo) {
        throw new functions.https.HttpsError(
            'permission-denied',
            'No tenés permisos de administrador para esta operación.'
        );
    }
}

// Verifica el ID token de Firebase enviado en el header Authorization de un
// onRequest (los onRequest no reciben context.auth automáticamente).
async function requireAdminFromRequestHeader(req) {
    const authHeader = req.get('Authorization') || '';
    const match = authHeader.match(/^Bearer (.+)$/);
    if (!match) {
        const err = new Error('Falta token de autenticación.');
        err.statusCode = 401;
        throw err;
    }
    const decoded = await admin.auth().verifyIdToken(match[1]);
    const db = admin.firestore();
    const userDoc = await db.collection('usuarios').doc(decoded.uid).get();
    const rol = userDoc.exists ? userDoc.data().rol : null;
    const activo = userDoc.exists ? (userDoc.data().activo ?? true) : false;
    if (rol !== 'admin' || !activo) {
        const err = new Error('No tenés permisos de administrador para esta operación.');
        err.statusCode = 403;
        throw err;
    }
}

// =========================================================================
// LOCK DE EMISIÓN FISCAL: serializa emisiones concurrentes de comprobantes
// para el mismo punto de venta + tipo, evitando que dos requests casi
// simultáneas pidan el mismo "próximo número" a ARCA.
// =========================================================================
async function conLockDeEmision(ptoVenta, cbteTipo, fn) {
    const db = admin.firestore();
    const lockRef = db.collection('locks_emision_fiscal').doc(`${ptoVenta}_${cbteTipo}`);
    const TTL_MS = 30000; // un lock más viejo que esto se considera abandonado

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(lockRef);
        const data = snap.exists ? snap.data() : null;
        const bloqueado = data && data.enCurso &&
            (Date.now() - (data.desde?.toMillis?.() ?? 0)) < TTL_MS;
        if (bloqueado) {
            throw new functions.https.HttpsError(
                'aborted',
                'Ya se está emitiendo otro comprobante para este punto de venta. Reintentá en unos segundos.'
            );
        }
        tx.set(lockRef, { enCurso: true, desde: admin.firestore.FieldValue.serverTimestamp() });
    });

    try {
        return await fn();
    } finally {
        await lockRef.set({ enCurso: false }, { merge: true });
    }
}

// =========================================================================
// SINCRONIZACIÓN CON PADEL MANAGER (AUTOMÁTICA & MANUAL)
// =========================================================================

// ⏰ Sincronización automática programada (Todos los lunes 03:00 AM - Sintaxis v2)
exports.sincronizarRankingPadelManager = onSchedule({
  schedule: '0 3 * * 1',
  timeZone: 'America/Argentina/Buenos_Aires',
}, async (event) => {
  return await ejecutarSincronizacionPadelManager();
});

// 🚀 Endpoint HTTP para sincronización bajo demanda desde Flutter
exports.sincronizarRankingManual = functions.https.onRequest(async (req, res) => {
  try {
    await requireAdminFromRequestHeader(req);
    const procesados = await ejecutarSincronizacionPadelManager();
    return res.status(200).json({ exito: true, procesados });
  } catch (error) {
    return res.status(error.statusCode || 500).json({ exito: false, error: error.toString() });
  }
});

async function ejecutarSincronizacionPadelManager() {
  const db = admin.firestore();
  const url = 'https://padelmanager.net/ranking';
  let actualizados = 0;

  try {
    const { data } = await axios.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0' }
    });
    const $ = cheerio.load(data);
    const listaJugadores = [];

    $('table tbody tr').each((_, element) => {
      const nombre = $(element).find('.jugador-nombre, .name').text().trim();
      const dni = $(element).find('.dni, .documento').text().trim().replace(/\./g, '');
      const categoria = $(element).find('.categoria, .cat').text().trim();
      const rating = parseInt($(element).find('.rating, .pts').text().trim(), 10) || 0;

      if (nombre) {
        listaJugadores.push({ nombre, dni, categoria, rating });
      }
    });

    const batch = db.batch();

    for (const j of listaJugadores) {
      let query;

      if (j.dni) {
        query = await db.collection('socios').where('dni', '==', j.dni).limit(1).get();
      }

      if ((!query || query.empty) && j.nombre) {
        query = await db.collection('socios').where('nombre', '==', j.nombre).limit(1).get();
      }

      if (query && !query.empty) {
        const docRef = query.docs[0].ref;
        batch.update(docRef, {
          categoriaPaddle: j.categoria,
          ratingPadelManager: j.rating,
          fechaUltimaSincroRanking: admin.firestore.FieldValue.serverTimestamp(),
        });
        actualizados++;
      }
    }

    await batch.commit();
    return actualizados;
  } catch (error) {
    console.error('🚨 Error sincronizando Padel Manager:', error);
    throw error;
  }
}

// =========================================================================
// MÓDULOS EXISTENTES (AFIP / ARCA & MERCADO PAGO)
// =========================================================================

// 🧮 Discrimina IVA a partir de un total con IVA incluido. Factura C
// (Monotributo, CbteTipo 11) nunca discrimina IVA — ImpNeto = total. Factura
// A/B (Responsable Inscripto) sí, usando la alícuota configurada (default
// 21%). Antes esto SIEMPRE mandaba ImpNeto=total/ImpIVA=0 sin importar el
// tipo de comprobante, lo cual es inválido para A/B.
// IDs de alícuota AFIP: 3=0%, 9=2.5%, 8=5%, 4=10.5%, 5=21%, 6=27%.
function discriminarIva(total, cbteTipo, alicuotaPorcentaje) {
    // 11/12/13 = Factura/ND/NC "C" (Monotributo): nunca discriminan IVA.
    if ([11, 12, 13].includes(cbteTipo)) {
        return { impNeto: total, impIva: 0, ivaArray: null };
    }
    const alicuota = alicuotaPorcentaje || 21;
    const impNeto = Math.round((total / (1 + alicuota / 100)) * 100) / 100;
    const impIva = Math.round((total - impNeto) * 100) / 100;
    const idsPorAlicuota = { 0: 3, 2.5: 9, 5: 8, 10.5: 4, 21: 5, 27: 6 };
    const idAlicuota = idsPorAlicuota[alicuota] || 5;
    return {
        impNeto,
        impIva,
        ivaArray: [{ 'Id': idAlicuota, 'BaseImp': impNeto, 'Importe': impIva }],
    };
}

// 🧾 CondicionIVAReceptorId (obligatorio desde RG 5616/2024). El club emite
// a personas físicas (socios), no a otras empresas, así que sólo Factura A
// (RI a RI, CbteTipo 1) asume receptor Responsable Inscripto; B y C asumen
// Consumidor Final, que es el caso real de un socio.
// Valores AFIP: 1=RI, 4=Exento, 5=Consumidor Final, 6=Monotributo.
function condicionIvaReceptor(cbteTipo) {
    // Familia "A" (Factura/ND/NC A = 1/2/3): receptor asumido Responsable
    // Inscripto. El resto (B/C y sus ND/NC): Consumidor Final.
    return [1, 2, 3].includes(cbteTipo) ? 1 : 5;
}

// 📅 Campos de servicio (obligatorios cuando Concepto es 2 o 3). 'concepto'
// llega del caller: 1=Productos (default, ej. buffet), 2=Servicios (ej.
// cuota social, inscripción a torneo), 3=Productos y Servicios (carritos
// mixtos). 'periodoDesde'/'periodoHasta' son 'YYYYMMDD'; si no llegan, se
// usa la fecha de emisión para ambos (el servicio se considera prestado el
// mismo día que se cobra).
function camposServicio(concepto, fechaEmision, periodoDesde, periodoHasta) {
    if (concepto === 1) return {};
    return {
        'FchServDesde': periodoDesde || fechaEmision,
        'FchServHasta': periodoHasta || fechaEmision,
        'FchVtoPago': fechaEmision,
    };
}

exports.emitirFacturaArca = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    const db = admin.firestore();
    try {
        const configDoc = await db.collection('configuraciones_fiscales').doc('arca_reglas').get();
        if (!configDoc.exists) {
            return { 'success': false, 'error': 'Falta configurar los parámetros fiscales en el panel de Administración.' };
        }
        const configFiscal = configDoc.data();
        const cuitClub = configFiscal.cuit;
        const ptoVenta = parseInt(configFiscal.puntoVenta ?? 1);
        const esProduccion = configFiscal.modoProduccion ?? false;
        const cbteTipo = parseInt(configFiscal.comprobanteTipo ?? 11);
        const alicuotaIva = parseFloat(configFiscal.alicuotaIvaPorcentaje ?? 21);

        const total = parseFloat(data.total);
        if (!Number.isFinite(total) || total <= 0) {
            return { 'success': false, 'error': 'Monto de factura inválido.' };
        }

        const concepto = [1, 2, 3].includes(parseInt(data.concepto)) ? parseInt(data.concepto) : 1;

        const afip = new Afip({
            'CUIT': cuitClub,
            'production': esProduccion,
            'cert': 'certificados/club_arca.crt',
            'key': 'certificados/club_arca.key'
        });

        const fecha = new Date(Date.now() - 3 * 3600 * 1000).toISOString().split('T')[0].replace(/-/g, '');
        const { impNeto, impIva, ivaArray } = discriminarIva(total, cbteTipo, alicuotaIva);

        const reqData = {
            'CantReg': 1, 'PtoVta': ptoVenta, 'CbteTipo': cbteTipo, 'Concepto': concepto,
            'DocTipo': data.socioDni ? 96 : 99, 'DocNro': data.socioDni ? parseInt(data.socioDni) : 0,
            'CbteDesde': 1, 'CbteHasta': 1, 'CbteFch': fecha, 'ImpTotal': total,
            'ImpTotConc': 0, 'ImpNeto': impNeto, 'ImpOpEx': 0, 'ImpIVA': impIva,
            'ImpTrib': 0, 'MonId': 'PES', 'MonCotiz': 1,
            'CondicionIVAReceptorId': condicionIvaReceptor(cbteTipo),
            ...camposServicio(concepto, fecha, data.periodoDesde, data.periodoHasta),
        };
        if (ivaArray) reqData.Iva = ivaArray;

        const res = await conLockDeEmision(ptoVenta, cbteTipo, async () => {
            const lastCbte = await afip.ElectronicBilling.getLastVoucher(reqData.PtoVta, reqData.CbteTipo);
            reqData.CbteDesde = lastCbte + 1;
            reqData.CbteHasta = lastCbte + 1;
            return await afip.ElectronicBilling.createVoucher(reqData);
        });

        return {
            'success': true, 'cae': res.CAE, 'vencimientoCae': res.CAEFchVto,
            'nroFactura': reqData.CbteDesde, 'puntoVenta': reqData.PtoVta, 'tipoComprobante': cbteTipo
        };
    } catch (error) {
        return { 'success': false, 'error': error.message };
    }
});

exports.emitirNotaCreditoDebitoArca = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    const db = admin.firestore();
    try {
        const configDoc = await db.collection('configuraciones_fiscales').doc('arca_reglas').get();
        if (!configDoc.exists) return { 'success': false, 'error': 'Falta configurar los parámetros fiscales.' };

        const configFiscal = configDoc.data();
        const cuitClub = configFiscal.cuit;
        const ptoVenta = parseInt(data.puntoVenta ?? configFiscal.puntoVenta ?? 1);
        const esProduccion = configFiscal.modoProduccion ?? false;
        const alicuotaIva = parseFloat(configFiscal.alicuotaIvaPorcentaje ?? 21);

        const cbteAsociadoTipo = parseInt(data.comprobanteAsociadoTipo ?? 11);
        const cbteAsociadoNro = parseInt(data.comprobanteAsociadoNro);
        const esCredito = data.esCredito ?? true;

        const monto = parseFloat(data.monto);
        if (!Number.isFinite(monto) || monto <= 0) {
            return { 'success': false, 'error': 'Monto inválido.' };
        }

        let cbteAjusteTipo = 13;
        if (cbteAsociadoTipo === 1) cbteAjusteTipo = esCredito ? 3 : 2;
        else if (cbteAsociadoTipo === 6) cbteAjusteTipo = esCredito ? 8 : 7;
        else if (cbteAsociadoTipo === 11) cbteAjusteTipo = esCredito ? 13 : 12;

        const afip = new Afip({
            'CUIT': cuitClub, 'production': esProduccion,
            'cert': 'certificados/club_arca.crt', 'key': 'certificados/club_arca.key'
        });

        const fecha = new Date(Date.now() - 3 * 3600 * 1000).toISOString().split('T')[0].replace(/-/g, '');
        const { impNeto, impIva, ivaArray } = discriminarIva(monto, cbteAjusteTipo, alicuotaIva);

        const reqData = {
            'CantReg': 1, 'PtoVta': ptoVenta, 'CbteTipo': cbteAjusteTipo, 'Concepto': 1,
            'DocTipo': 99, 'DocNro': 0, 'CbteDesde': 1, 'CbteHasta': 1, 'CbteFch': fecha,
            'ImpTotal': monto, 'ImpTotConc': 0, 'ImpNeto': impNeto,
            'ImpOpEx': 0, 'ImpIVA': impIva, 'ImpTrib': 0, 'MonId': 'PES', 'MonCotiz': 1,
            'CondicionIVAReceptorId': condicionIvaReceptor(cbteAjusteTipo),
            'CbtesAsoc': [{'Tipo': cbteAsociadoTipo, 'PtoVta': ptoVenta, 'Nro': cbteAsociadoNro}]
        };
        if (ivaArray) reqData.Iva = ivaArray;

        const res = await conLockDeEmision(ptoVenta, cbteAjusteTipo, async () => {
            const lastCbte = await afip.ElectronicBilling.getLastVoucher(reqData.PtoVta, reqData.CbteTipo);
            reqData.CbteDesde = lastCbte + 1;
            reqData.CbteHasta = lastCbte + 1;
            return await afip.ElectronicBilling.createVoucher(reqData);
        });

        return {
            'success': true, 'cae': res.CAE, 'vencimientoCae': res.CAEFchVto,
            'nroComprobante': reqData.CbteDesde, 'tipoComprobante': cbteAjusteTipo
        };
    } catch (error) {
        return { 'success': false, 'error': error.message };
    }
});

exports.probarConexionArca = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    try {
        const cuit = parseInt(data.cuit);
        const ptoVenta = parseInt(data.puntoVenta ?? 1);
        const esProduccion = data.modoProduccion ?? false;

        const afip = new Afip({ 
            'CUIT': cuit, 'production': esProduccion, 
            'cert': 'certificados/club_arca.crt', 'key': 'certificados/club_arca.key' 
        });

        const status = await afip.ElectronicBilling.getServerStatus();
        return { 'success': true, 'status': status.AppServer, 'dbServer': status.DbServer, 'authServer': status.AuthServer };
    } catch (error) {
        return { 'success': false, 'error': error.message };
    }
});

exports.crearCobroMercadoPago = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    try {
        const { concepto, ventaId } = data;
        const db = admin.firestore();

        // 🚨 El monto se lee SIEMPRE de la venta real en Firestore, nunca del
        // cliente: antes `monto` venía directo del caller, así que se podía
        // crear una preferencia de $1 apuntando (external_reference) a una
        // venta real de mayor valor, y el webhook la marcaba "Aprobado".
        if (!ventaId) return { success: false, error: 'Falta ventaId.' };
        const ventaSnap = await db.collection('ventas_buffet').doc(ventaId).get();
        if (!ventaSnap.exists) return { success: false, error: 'La venta no existe.' };
        const ventaData = ventaSnap.data();
        if (ventaData.estadoPagoMP === 'Aprobado') {
            return { success: false, error: 'Esta venta ya fue cobrada.' };
        }
        const monto = parseFloat(ventaData.total);
        if (!Number.isFinite(monto) || monto <= 0) {
            return { success: false, error: 'La venta no tiene un total válido.' };
        }

        const configSnap = await db.collection('configuraciones_fiscales').doc('mp_reglas').get();
        if (!configSnap.exists) return { success: false, error: "Falta configurar credenciales MP." };
        const accessToken = configSnap.data().accessToken;

        const response = await axios.post(
            'https://api.mercadopago.com/checkout/preferences',
            {
                items: [{ title: concepto || 'Consumo Aqua & Paddle Club', quantity: 1, currency_id: 'ARS', unit_price: monto }],
                external_reference: ventaId,
                notification_url: `https://us-central1-${process.env.GCP_PROJECT || process.env.GCLOUD_PROJECT}.cloudfunctions.net/webhookMercadoPago`,
            },
            { headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' } }
        );

        return { success: true, initPoint: response.data.init_point, preferenceId: response.data.id };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

exports.webhookMercadoPago = functions.https.onRequest(async (req, res) => {
    try {
        const { type, data } = req.body;
        if (type === 'payment' && data && data.id) {
            const paymentId = data.id;
            const db = admin.firestore();
            const configSnap = await db.collection('configuraciones_fiscales').doc('mp_reglas').get();
            if (configSnap.exists) {
                const accessToken = configSnap.data().accessToken;
                const mpRes = await axios.get(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
                    headers: { 'Authorization': `Bearer ${accessToken}` }
                });
                const paymentData = mpRes.data;
                const ventaId = paymentData.external_reference;

                if (paymentData.status === 'approved' && ventaId) {
                    const ventaRef = db.collection('ventas_buffet').doc(ventaId);
                    const ventaSnap = await ventaRef.get();
                    // 🚨 Además de que crearCobroMercadoPago ya fija el precio desde
                    // la venta real, se re-valida acá que lo efectivamente pagado en
                    // MP coincida con el total de la venta antes de marcarla Aprobada.
                    const totalVenta = ventaSnap.exists ? parseFloat(ventaSnap.data().total) : null;
                    const montoPagado = parseFloat(paymentData.transaction_amount);
                    if (
                        ventaSnap.exists &&
                        Number.isFinite(totalVenta) &&
                        Number.isFinite(montoPagado) &&
                        Math.abs(montoPagado - totalVenta) < 1
                    ) {
                        await ventaRef.update({
                            estadoPagoMP: 'Aprobado',
                            medio_pago: 'Mercado Pago (QR)',
                            mpPaymentId: paymentId,
                            fechaPagoMP: admin.firestore.FieldValue.serverTimestamp(),
                        });
                    } else {
                        console.error(`🚨 Monto pagado (${montoPagado}) no coincide con el total de la venta ${ventaId} (${totalVenta}).`);
                    }
                }
            }
        }
        res.status(200).send('OK');
    } catch (error) {
        res.status(500).send('Error');
    }
});

// ⚠️ El servicio de WhatsApp (QR, envío de mensajes) vive en server.js,
// desplegado por separado (Render). El bloque que estaba acá referenciaba
// una variable `client` inexistente y rompía la carga de TODAS las
// Cloud Functions de este archivo en cada deploy/cold start.