const { setGlobalOptions } = require("firebase-functions");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler"); // 👈 Importamos onSchedule para v2
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
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

// 🚨 notificaciones.js define 'notificarInscripcionTorneo' y
// 'notificarReservaCancha' (push FCM al inscribirse a un torneo / reservar
// cancha), pero Firebase sólo despliega lo que exporta el archivo 'main'
// de package.json (index.js) — como nada acá hacía require('./notificaciones'),
// esos dos triggers nunca se desplegaban: vivían en el repo pero no existían
// en producción.
Object.assign(exports, require('./notificaciones'));

// =========================================================================
// AUTORIZACIÓN: sólo usuarios con rol 'admin' en /usuarios/{uid} pueden
// operar los callables fiscales (AFIP/ARCA) y de cobro (Mercado Pago).
// Antes ninguno de estos onCall verificaba context.auth, así que cualquiera
// con la API key pública del proyecto podía invocarlos directo por HTTPS.
//
// 💸 OPTIMIZACIÓN DE COSTO: el rol/activo se leía con un get() a Firestore
// en CADA llamada — con 'esStaffOperativo' evaluando además esCajero(), eso
// eran 2 lecturas extra por operación. Ahora se lee primero del ID token
// (Custom Claims, sin costo ni lectura) y sólo si todavía no están
// sincronizadas ahí (usuario recién creado/editado, antes de que se le
// renueve el token) se cae al get() de siempre. A medida que los tokens se
// renuevan solos (o el usuario vuelve a loguearse) el sistema converge solo
// a costo cero sin ningún corte de acceso en el medio.
// =========================================================================
async function requireAdmin(context) {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Necesitás iniciar sesión para realizar esta operación.'
        );
    }
    const claims = context.auth.token || {};
    if (claims.rol === 'admin' && claims.activo === true) return;

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

// Igual que requireAdmin pero también deja pasar al rol 'cajero' — para las
// operaciones de POS/caja (cobrar, facturar una venta) que un cajero hace
// todos los días y que antes quedaban bloqueadas por error al no existir
// ningún rol intermedio entre 'admin' y todo lo demás.
async function requireStaffOperativo(context) {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Necesitás iniciar sesión para realizar esta operación.'
        );
    }
    const claims = context.auth.token || {};
    if ((claims.rol === 'admin' || claims.rol === 'cajero') && claims.activo === true) return;

    const db = admin.firestore();
    const userDoc = await db.collection('usuarios').doc(context.auth.uid).get();
    const rol = userDoc.exists ? userDoc.data().rol : null;
    const activo = userDoc.exists ? (userDoc.data().activo ?? true) : false;
    if ((rol !== 'admin' && rol !== 'cajero') || !activo) {
        throw new functions.https.HttpsError(
            'permission-denied',
            'No tenés permisos para realizar esta operación.'
        );
    }
}

// =========================================================================
// CUSTOM CLAIMS: sincroniza rol/activo de /usuarios/{uid} al ID token de
// Firebase Auth, para que las Reglas de Seguridad y los checks de arriba
// puedan verificar permisos SIN leer Firestore. Se dispara solo en cada
// alta/edición de usuario (trigger) — no hace falta llamarlo a mano.
// =========================================================================
async function sincronizarClaimsUsuario(uid, datosUsuario) {
    if (!datosUsuario) {
        // El documento se borró: no queda rol que sincronizar.
        await admin.auth().setCustomUserClaims(uid, { rol: null, activo: false });
        await admin.auth().revokeRefreshTokens(uid).catch(() => {});
        return;
    }
    const rol = datosUsuario.rol ?? 'socio';
    const activo = datosUsuario.activo ?? true;
    await admin.auth().setCustomUserClaims(uid, { rol, activo });
    // 🔒 Si se desactiva la cuenta (o se le baja el rol), se revocan sus
    // tokens de refresco: no puede sacar un ID token nuevo con el rol
    // viejo. El token YA emitido sigue siendo válido hasta que expire por
    // su cuenta (hasta 1 hora) — es el trade-off aceptado de usar Custom
    // Claims en vez de leer Firestore en cada request.
    if (!activo) {
        await admin.auth().revokeRefreshTokens(uid).catch(() => {});
    }
}

exports.sincronizarCustomClaims = onDocumentWritten('usuarios/{uid}', async (event) => {
    const uid = event.params.uid;
    const despues = event.data.after.exists ? event.data.after.data() : null;
    try {
        await sincronizarClaimsUsuario(uid, despues);
    } catch (error) {
        logger.error(`No se pudo sincronizar Custom Claims de ${uid}: ${error.message}`);
    }
});

// 🧪 Backfill único: sincroniza los Custom Claims de TODOS los usuarios ya
// existentes (el trigger de arriba sólo cubre altas/ediciones nuevas desde
// que se desplegó). Sin esto, los usuarios viejos seguirían cayendo siempre
// al get() de respaldo hasta la próxima vez que se les edite el rol.
exports.backfillCustomClaims = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    const db = admin.firestore();
    const snap = await db.collection('usuarios').get();
    let sincronizados = 0;
    for (const doc of snap.docs) {
        try {
            await sincronizarClaimsUsuario(doc.id, doc.data());
            sincronizados++;
        } catch (error) {
            logger.warn(`Backfill: no se pudo sincronizar ${doc.id}: ${error.message}`);
        }
    }
    return { success: true, sincronizados, total: snap.size };
});

// =========================================================================
// AUDITORÍA: registro inmutable (create-only, ver firestore.rules) de
// operaciones sensibles. Antes no existía ningún registro centralizado —
// 'auditoria_movimientos_caja' figuraba en las reglas pero nada la escribía.
// =========================================================================
async function registrarAuditoria(db, context, { accion, entidad, entidadId, detalle }) {
    try {
        await db.collection('auditoria_sistema').add({
            accion,
            entidad,
            entidadId: entidadId ?? null,
            detalle: detalle ?? {},
            uid: context.auth ? context.auth.uid : null,
            email: context.auth && context.auth.token ? (context.auth.token.email ?? null) : null,
            fecha: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (error) {
        logger.warn(`No se pudo registrar auditoría (${accion}): ${error.message}`);
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
    // esStaffOperativo (no sólo esAdmin): emitir el comprobante de una venta
    // normal en POS es una tarea de cajero, no de configuración fiscal.
    await requireStaffOperativo(context);
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

        await registrarAuditoria(db, context, {
            accion: 'emitir_factura_arca',
            entidad: 'ventas_buffet',
            detalle: { total, cae: res.CAE, nroFactura: reqData.CbteDesde, puntoVenta: reqData.PtoVta, tipoComprobante: cbteTipo, socioDni: data.socioDni ?? null },
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

        await registrarAuditoria(db, context, {
            accion: esCredito ? 'emitir_nota_credito_arca' : 'emitir_nota_debito_arca',
            entidad: 'ajustes_fiscales_nc_nd',
            detalle: { monto, cae: res.CAE, nroComprobante: reqData.CbteDesde, comprobanteAsociadoNro: cbteAsociadoNro },
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

// 💳 MERCADO PAGO — genérico por RUTA DE DOCUMENTO, no por colección fija.
// Antes esto sólo servía ventas de POS (ventas_buffet.total como colección
// plana). Se generaliza acá para poder cobrar también reservas de cancha,
// cuotas sociales (socios/{id}/cuenta_corriente/{movId}, una SUBcolección)
// e inscripciones a torneo con el mismo par de funciones, sin duplicar la
// lógica de validación. Como ambas exigen requireAdmin, sólo personal de
// staff autenticado puede apuntar a una ruta — nunca un socio/cliente.
//
// El detalle de cada cobro (a qué documento corresponde, con qué campo de
// monto/medio de pago) se guarda en 'mp_cobros_pendientes', indexado por un
// ID corto que viaja como external_reference — Mercado Pago sólo devuelve
// esa referencia en el webhook, así que hace falta este lado servidor para
// saber dónde y cómo aplicar la confirmación. De paso, esa colección queda
// como bitácora/auditoría de todos los cobros MP intentados.
// Núcleo compartido por TODAS las formas de cobro (QR/Checkout Pro, Posnet/
// Point y, indirectamente, crearCobroMercadoPagoSocio) — valida el monto
// real contra Firestore y abre el registro en 'mp_cobros_pendientes'. Lo
// que varía entre QR y Posnet es sólo a qué endpoint de MP se llama
// DESPUÉS de esto (ver _generarPreferenciaMercadoPago vs
// crearCobroMercadoPagoPosnet).
async function _validarYRegistrarCobroMP({
    ruta, campoMonto, campoMedioPago, concepto, creadoPor, aplicarSaldoA,
}) {
    const db = admin.firestore();
    const nombreCampoMonto = campoMonto || 'total';
    const nombreCampoMedioPago = campoMedioPago || 'medio_pago';

    // 🚨 El monto se lee SIEMPRE del documento real en Firestore, nunca
    // del cliente: si viniera del caller, se podría crear un cobro de $1
    // apuntando a un comprobante real de mayor valor y el webhook lo
    // marcaría "Aprobado" igual.
    const docSnap = await db.doc(ruta).get();
    if (!docSnap.exists) return { error: 'El comprobante no existe.' };
    const docData = docSnap.data();
    if (docData.estadoPagoMP === 'Aprobado') {
        return { error: 'Esto ya fue cobrado.' };
    }
    const monto = parseFloat(docData[nombreCampoMonto]);
    if (!Number.isFinite(monto) || monto <= 0) {
        return { error: 'El comprobante no tiene un monto válido.' };
    }

    const configSnap = await db.collection('configuraciones_fiscales').doc('mp_reglas').get();
    if (!configSnap.exists) return { error: 'Falta configurar credenciales MP.' };
    const accessToken = configSnap.data().accessToken;

    const cobroRef = db.collection('mp_cobros_pendientes').doc();
    await cobroRef.set({
        ruta,
        campoMonto: nombreCampoMonto,
        campoMedioPago: nombreCampoMedioPago,
        concepto: concepto || null,
        monto,
        estado: 'Pendiente',
        creadoEl: admin.firestore.FieldValue.serverTimestamp(),
        creadoPor,
        ...(aplicarSaldoA ? { aplicarSaldoA } : {}),
    });

    return { monto, accessToken, cobroRef };
}

async function _generarPreferenciaMercadoPago({
    ruta, campoMonto, campoMedioPago, concepto, creadoPor, aplicarSaldoA,
}) {
    const resultado = await _validarYRegistrarCobroMP({
        ruta, campoMonto, campoMedioPago, concepto, creadoPor, aplicarSaldoA,
    });
    if (resultado.error) return { success: false, error: resultado.error };
    const { monto, accessToken, cobroRef } = resultado;

    const response = await axios.post(
        'https://api.mercadopago.com/checkout/preferences',
        {
            items: [{ title: concepto || 'Consumo Aqua & Paddle Club', quantity: 1, currency_id: 'ARS', unit_price: monto }],
            external_reference: cobroRef.id,
            notification_url: `https://us-central1-${process.env.GCP_PROJECT || process.env.GCLOUD_PROJECT}.cloudfunctions.net/webhookMercadoPago`,
        },
        { headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' } }
    );

    return {
        success: true,
        initPoint: response.data.init_point,
        preferenceId: response.data.id,
        cobroId: cobroRef.id,
        // El self-service (crearCobroMercadoPagoSocio) no conoce la 'ruta'
        // de antemano — la resuelve este helper — así que hace falta
        // devolverla para que el cliente sepa qué documento escuchar.
        ruta,
    };
}

exports.crearCobroMercadoPago = functions.https.onCall(async (data, context) => {
    // esStaffOperativo: generar el QR de cobro en POS/canchas/cuotas es
    // parte normal de la operación de caja.
    await requireStaffOperativo(context);
    try {
        const { concepto, ruta, campoMonto, campoMedioPago } = data;
        if (!ruta) return { success: false, error: 'Falta la ruta del comprobante.' };
        return await _generarPreferenciaMercadoPago({
            ruta, campoMonto, campoMedioPago, concepto, creadoPor: context.auth.uid,
        });
    } catch (error) {
        return { success: false, error: error.message };
    }
});

// =========================================================================
// 📟 MERCADO PAGO POINT — cobro con terminal física (posnet), para cerrar
// el circuito de caja cuando el cliente paga con tarjeta en el mostrador en
// vez de escanear el QR. Usa la Orders API de MP (POST /v1/orders con
// type:'point'), que es la que Mercado Pago tiene vigente hoy — la API
// anterior ("Payment Intents", POST /point/integration-api/devices/.../
// payment-intents) está en baja y Mercado Pago ya no acepta nuevas
// integraciones sobre ella.
//
// ⚠️ Sin un dispositivo Point real vinculado a la cuenta (en modo PDV, con
// caja/sucursal asociada) no hay forma de probar esto end-to-end desde
// acá — queda implementado contra la documentación oficial vigente, pero
// sin verificación con hardware real. Antes de usarlo en caja:
//   1) Tener al menos un Point vinculado a la cuenta de MP del club.
//   2) En el panel de MP (Tus integraciones > tu app > Webhooks > modo
//      productivo) suscribir el tópico "Order" a la URL de
//      webhookMercadoPagoOrder (ver más abajo) — a diferencia del cobro
//      por QR, este webhook NO se registra solo al crear el cobro.
// =========================================================================

// Lista las terminales Point vinculadas a la cuenta — así la pantalla de
// cobro puede ofrecer un selector en vez de pedirle al cajero que tipee un
// terminal_id de memoria.
exports.listarTerminalesPosnetMP = functions.https.onCall(async (data, context) => {
    await requireStaffOperativo(context);
    try {
        const db = admin.firestore();
        const configSnap = await db.collection('configuraciones_fiscales').doc('mp_reglas').get();
        if (!configSnap.exists) return { success: false, error: 'Falta configurar credenciales MP.' };
        const accessToken = configSnap.data().accessToken;

        const response = await axios.get('https://api.mercadopago.com/terminals/v1/list', {
            headers: { 'Authorization': `Bearer ${accessToken}` },
        });
        const terminales = (response.data?.data?.terminals || []).map((t) => ({
            id: t.id,
            posId: t.pos_id,
            storeId: t.store_id,
            modoOperacion: t.operating_mode,
        }));
        return { success: true, terminales };
    } catch (error) {
        return { success: false, error: error.response?.data?.message || error.message };
    }
});

// Envía el cobro a una terminal Point puntual — el cliente completa el pago
// (tarjeta/contactless) directo en el aparato. La confirmación llega por
// webhookMercadoPagoOrder, igual que el QR llega por webhookMercadoPago.
exports.crearCobroMercadoPagoPosnet = functions.https.onCall(async (data, context) => {
    await requireStaffOperativo(context);
    try {
        const { concepto, ruta, campoMonto, campoMedioPago, terminalId } = data;
        if (!ruta) return { success: false, error: 'Falta la ruta del comprobante.' };
        if (!terminalId) return { success: false, error: 'Falta elegir la terminal Posnet.' };

        const resultado = await _validarYRegistrarCobroMP({
            ruta, campoMonto, campoMedioPago, concepto, creadoPor: context.auth.uid,
        });
        if (resultado.error) return { success: false, error: resultado.error };
        const { monto, accessToken, cobroRef } = resultado;

        let response;
        try {
            response = await axios.post(
                'https://api.mercadopago.com/v1/orders',
                {
                    type: 'point',
                    external_reference: cobroRef.id,
                    transactions: { payments: [{ amount: monto.toFixed(2) }] },
                    config: { point: { terminal_id: terminalId } },
                    description: concepto || 'Consumo Aqua & Paddle Club',
                },
                {
                    headers: {
                        'Authorization': `Bearer ${accessToken}`,
                        'Content-Type': 'application/json',
                        // Reutilizar el id del cobro como idempotency key: un
                        // reintento del mismo cobro (mismo body) no crea una
                        // orden duplicada en la terminal.
                        'X-Idempotency-Key': cobroRef.id,
                    },
                }
            );
        } catch (mpError) {
            // 409 already_queued_order_for_terminal: la terminal ya tiene
            // una orden sin resolver — hay que cancelarla antes de mandar
            // otra (ver cancelarCobroPosnetMP).
            const detalle = mpError.response?.data;
            await cobroRef.update({ estado: 'Error', errorMP: detalle?.message || mpError.message });
            if (detalle?.message === 'already_queued_order_for_terminal') {
                return {
                    success: false,
                    error: 'Esa terminal ya tiene un cobro pendiente sin terminar. Cancelalo en la terminal o desde el sistema antes de reintentar.',
                };
            }
            return { success: false, error: detalle?.message || mpError.message };
        }

        await cobroRef.update({ mpOrderId: response.data.id, terminalId });

        return {
            success: true,
            orderId: response.data.id,
            cobroId: cobroRef.id,
            ruta,
        };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

// Cancela una orden Posnet todavía no resuelta (útil si el cajero se
// equivocó de monto, o para destrabar el 409 already_queued_order_for_terminal
// de arriba). Sólo funciona mientras la orden siga 'created' o 'at_terminal'.
exports.cancelarCobroPosnetMP = functions.https.onCall(async (data, context) => {
    await requireStaffOperativo(context);
    try {
        const { cobroId } = data;
        if (!cobroId) return { success: false, error: 'Falta el id del cobro.' };
        const db = admin.firestore();
        const cobroRef = db.collection('mp_cobros_pendientes').doc(cobroId);
        const cobroSnap = await cobroRef.get();
        if (!cobroSnap.exists || !cobroSnap.data().mpOrderId) {
            return { success: false, error: 'No se encontró la orden de Mercado Pago para ese cobro.' };
        }
        const configSnap = await db.collection('configuraciones_fiscales').doc('mp_reglas').get();
        const accessToken = configSnap.data().accessToken;

        await axios.post(
            `https://api.mercadopago.com/v1/orders/${cobroSnap.data().mpOrderId}/cancel`,
            {},
            {
                headers: {
                    'Authorization': `Bearer ${accessToken}`,
                    // La orden puede estar ya 'at_terminal' (mostrada en el
                    // aparato) — sin este header la API rechaza la
                    // cancelación en ese estado.
                    'x-allow-cancelable-status': 'at_terminal',
                },
            }
        );
        await cobroRef.update({ estado: 'Cancelado' });
        return { success: true };
    } catch (error) {
        return { success: false, error: error.response?.data?.message || error.message };
    }
});

// 💳 Pago online SELF-SERVICE (el socio paga desde su propio dashboard, sin
// staff de por medio) — a diferencia de crearCobroMercadoPago, acá la 'ruta'
// NUNCA la decide el cliente: la resuelve y valida este mismo callable a
// partir de context.auth.uid, para que un socio jamás pueda apuntar a un
// comprobante ajeno.
exports.crearCobroMercadoPagoSocio = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Necesitás iniciar sesión para pagar.');
    }
    const db = admin.firestore();
    const { tipo, reservaId } = data;

    // 🚨 El id del doc 'socios/{id}' NO es el uid de Auth — son altas
    // migradas/creadas por el admin con id propio, vinculadas recién
    // después vía 'usuarioUid' (mismo criterio que reserva_cancha_screen.dart).
    const querySocio = await db.collection('socios')
        .where('usuarioUid', '==', context.auth.uid)
        .limit(1)
        .get();
    if (querySocio.empty) {
        return { success: false, error: 'No encontramos tu ficha de socio.' };
    }
    const socioDoc = querySocio.docs[0];
    const socioId = socioDoc.id;

    try {
        if (tipo === 'cuota') {
            const saldo = parseFloat(socioDoc.data().saldoCuentaCorriente) || 0;
            if (saldo >= 0) {
                return { success: false, error: 'No tenés saldo pendiente para pagar.' };
            }
            const monto = Math.abs(saldo);
            // Se crea un movimiento nuevo por el total adeudado al momento
            // de pagar (el saldo es un acumulado, no hay un único
            // comprobante "pendiente" al que apuntar) — el webhook, al
            // aprobarlo, suma 'monto' de vuelta al saldo (ver aplicarSaldoA).
            const movRef = socioDoc.ref.collection('cuenta_corriente').doc();
            await movRef.set({
                tipo: 'Pago Mercado Pago',
                concepto: 'Pago de cuota social vía Mercado Pago',
                monto,
                estado: 'Pendiente',
                fecha: admin.firestore.FieldValue.serverTimestamp(),
                creadoPor: context.auth.uid,
            });
            return await _generarPreferenciaMercadoPago({
                ruta: movRef.path,
                campoMonto: 'monto',
                campoMedioPago: 'medioPago',
                concepto: 'Pago de cuota social - Aqua & Paddle Club',
                creadoPor: context.auth.uid,
                aplicarSaldoA: socioId,
            });
        }

        if (tipo === 'reserva_cancha') {
            if (!reservaId) return { success: false, error: 'Falta la reserva.' };
            const reservaRef = db.collection('reservas_canchas').doc(reservaId);
            const reservaSnap = await reservaRef.get();
            if (!reservaSnap.exists) return { success: false, error: 'La reserva no existe.' };
            if (reservaSnap.data().socioId !== socioId) {
                throw new functions.https.HttpsError('permission-denied', 'Esa reserva no te pertenece.');
            }
            return await _generarPreferenciaMercadoPago({
                ruta: reservaRef.path,
                campoMonto: 'precio',
                campoMedioPago: 'metodoPago',
                concepto: 'Alquiler de cancha - Aqua & Paddle Club',
                creadoPor: context.auth.uid,
            });
        }

        return { success: false, error: 'Tipo de cobro no reconocido.' };
    } catch (error) {
        if (error instanceof functions.https.HttpsError) throw error;
        return { success: false, error: error.message };
    }
});

// Núcleo compartido por webhookMercadoPago (QR/Checkout Pro, topic
// 'payment') y webhookMercadoPagoOrder (Posnet/Point, topic 'order') — una
// vez confirmado el pago en MP, marca el comprobante real y el cobro como
// Aprobados, y si corresponde acredita el saldo del socio. Devuelve false
// sin tocar nada si el monto pagado no coincide con lo registrado.
async function _aplicarAprobacionCobroMP({ db, cobroRef, cobroData, montoPagado, medioPagoLabel, mpReferenciaId }) {
    const { ruta, campoMedioPago, monto, aplicarSaldoA } = cobroData;
    if (!(Number.isFinite(montoPagado) && Math.abs(montoPagado - monto) < 1)) {
        console.error(`🚨 Monto pagado (${montoPagado}) no coincide con el cobro pendiente ${cobroRef.id} (${monto}).`);
        return false;
    }
    const batch = db.batch();
    batch.update(db.doc(ruta), {
        estadoPagoMP: 'Aprobado',
        [campoMedioPago]: medioPagoLabel,
        mpPaymentId: mpReferenciaId,
        fechaPagoMP: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(cobroRef, {
        estado: 'Aprobado',
        mpPaymentId: mpReferenciaId,
        fechaAprobacion: admin.firestore.FieldValue.serverTimestamp(),
    });
    // 💰 Pago de cuota social (crearCobroMercadoPagoSocio, tipo 'cuota'): el
    // saldo real vive en 'socios/{id}.saldoCuentaCorriente', no en el
    // movimiento en sí — sumarle lo pagado cancela la deuda (el saldo es
    // negativo mientras haya deuda).
    if (aplicarSaldoA) {
        batch.update(db.collection('socios').doc(aplicarSaldoA), {
            saldoCuentaCorriente: admin.firestore.FieldValue.increment(monto),
        });
    }
    await batch.commit();
    return true;
}

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
                const cobroId = paymentData.external_reference;

                if (paymentData.status === 'approved' && cobroId) {
                    const cobroRef = db.collection('mp_cobros_pendientes').doc(cobroId);
                    const cobroSnap = await cobroRef.get();

                    if (cobroSnap.exists && cobroSnap.data().estado !== 'Aprobado') {
                        await _aplicarAprobacionCobroMP({
                            db,
                            cobroRef,
                            cobroData: cobroSnap.data(),
                            montoPagado: parseFloat(paymentData.transaction_amount),
                            medioPagoLabel: 'Mercado Pago (QR)',
                            mpReferenciaId: paymentId,
                        });
                    }
                }
            }
        }
        res.status(200).send('OK');
    } catch (error) {
        res.status(500).send('Error');
    }
});

// Confirmación de los cobros por terminal Posnet (crearCobroMercadoPagoPosnet)
// — a diferencia del QR, MP notifica esto con el tópico 'order', no
// 'payment', y manda el estado y el external_reference directo en el body
// (no hace falta un GET adicional para consultarlo). ⚠️ Esta suscripción NO
// se crea sola: hay que darla de alta a mano en el panel de MP (Tus
// integraciones > tu app > Webhooks > modo productivo > tópico "Order"),
// apuntando a la URL de esta función.
exports.webhookMercadoPagoOrder = functions.https.onRequest(async (req, res) => {
    try {
        const { type, action, data } = req.body;
        if (type === 'order' && data && data.id) {
            const db = admin.firestore();
            const cobroId = data.external_reference;
            const estadoOrder = data.status;

            if (cobroId) {
                const cobroRef = db.collection('mp_cobros_pendientes').doc(cobroId);
                const cobroSnap = await cobroRef.get();

                if (cobroSnap.exists && cobroSnap.data().estado !== 'Aprobado') {
                    if (action === 'order.processed' && estadoOrder === 'processed') {
                        const montoPagado = parseFloat(data.total_paid_amount);
                        await _aplicarAprobacionCobroMP({
                            db,
                            cobroRef,
                            cobroData: cobroSnap.data(),
                            montoPagado,
                            medioPagoLabel: 'Mercado Pago (Posnet)',
                            mpReferenciaId: data.id,
                        });
                    } else if (['order.canceled', 'order.failed', 'order.expired'].includes(action)) {
                        await cobroRef.update({ estado: 'Error', errorMP: data.status_detail || estadoOrder });
                    }
                    // 'order.action_required' (modo PDV: falta confirmar en
                    // la terminal) no cambia nada acá — se espera el
                    // próximo evento (processed/failed/canceled).
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

// =========================================================================
// 📲 RELAY DE WHATSAPP PARA LLAMADAS NO-ADMIN (socios)
// =========================================================================
// server.js exige un ID token de Firebase de un usuario con rol 'admin' en
// /usuarios/{uid} para /send-whatsapp — correcto para las pantallas de
// staff, pero un socio autenticado nunca tiene ese rol, así que la
// confirmación de su propia reserva y el aviso de comprobante adjunto al
// administrador fallaban siempre (401) al llamar el endpoint directo.
//
// Esta función es el único puente permitido para esos dos casos: valida que
// quien llama sea un socio vinculado real (no cualquier cuenta autenticada
// al azar), decide el destinatario EN EL SERVIDOR (nunca confía en un
// teléfono que mande el cliente — así no se puede usar para mandar spam a
// un número arbitrario), y "toma prestado" un token de un admin activo
// (via intercambio de un custom token con la Web API Key pública del
// proyecto — la misma que ya viaja embebida en el bundle de Flutter Web en
// lib/firebase_options.dart, no es un secreto) para poder invocar el
// bridge de WhatsApp sin tener que agregarle un segundo mecanismo de auth
// ni redeployar server.js en Render.
async function obtenerIdTokenDeAdminActivo(db) {
    const adminSnap = await db.collection('usuarios')
        .where('rol', '==', 'admin')
        .where('activo', '==', true)
        .limit(1)
        .get();
    if (adminSnap.empty) {
        throw new Error('No hay administradores activos configurados para enviar notificaciones.');
    }
    const customToken = await admin.auth().createCustomToken(adminSnap.docs[0].id);
    const webApiKey = 'AIzaSyAMuXW3-rXtigeGmSFVYeKupPEqZkQQ2Lc'; // Web API Key pública (lib/firebase_options.dart)
    const resp = await axios.post(
        `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${webApiKey}`,
        { token: customToken, returnSecureToken: true }
    );
    return resp.data.idToken;
}

exports.notificarWhatsappSocio = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Necesitás iniciar sesión.');
    }
    const db = admin.firestore();

    const socioSnap = await db.collection('socios')
        .where('usuarioUid', '==', context.auth.uid)
        .limit(1)
        .get();
    if (socioSnap.empty) {
        throw new functions.https.HttpsError('permission-denied', 'Sólo socios vinculados pueden usar esta función.');
    }
    const socioData = socioSnap.docs[0].data();

    const { tipo, mensaje } = data;
    if (!mensaje) return { success: false, error: 'Falta el mensaje.' };

    let telefonoDestino;
    if (tipo === 'notificar_admin') {
        // Ignora cualquier teléfono que mande el cliente: siempre al admin
        // configurado en el panel (Administración > Parámetros Fiscales > WhatsApp).
        const configSnap = await db.collection('configuraciones_fiscales').doc('whatsapp_reglas').get();
        telefonoDestino = configSnap.exists ? configSnap.data().telefonoAdmin : null;
        if (!telefonoDestino) {
            return { success: false, error: 'No hay un teléfono de administrador configurado.' };
        }
    } else if (tipo === 'notificar_propio') {
        // Sólo puede mandarse el mensaje al teléfono YA REGISTRADO del socio
        // que llama, nunca a uno arbitrario provisto por el cliente.
        telefonoDestino = socioData.telefono;
        if (!telefonoDestino) {
            return { success: false, error: 'No tenés un teléfono registrado en tu ficha.' };
        }
    } else {
        return { success: false, error: 'Tipo de notificación inválido.' };
    }

    try {
        const idTokenAdmin = await obtenerIdTokenDeAdminActivo(db);
        const resp = await axios.post(
            'https://servicio-whatsapp-oqua.onrender.com/send-whatsapp',
            { phone: telefonoDestino, message: mensaje },
            { headers: { Authorization: `Bearer ${idTokenAdmin}` } }
        );
        return { success: resp.data && resp.data.success === true, error: resp.data ? resp.data.error : undefined };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

// =========================================================================
// RECORDATORIOS AUTOMÁTICOS POR WHATSAPP — cuota pendiente, apto médico
// vencido/por vencer y reservas de cancha del día siguiente. Antes esto
// dependía de que alguien del staff se acordara de avisar a mano.
// =========================================================================

function limpiarTelefonoAr(telefono) {
    let limpio = (telefono || '').toString().replace(/\D/g, '');
    if (!limpio) return '';
    if (limpio.startsWith('0')) limpio = limpio.substring(1);
    if (limpio.startsWith('15')) limpio = limpio.substring(2);
    if (!limpio.startsWith('54')) limpio = `549${limpio}`;
    return limpio;
}

function esperar(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

// 🔔 Push (FCM) como segundo canal del recordatorio de cuota, además del
// WhatsApp — antes, si Baileys perdía la sesión de WhatsApp (pasa: hay que
// re-escanear el QR cada tanto) o el socio no tenía teléfono cargado,
// quedaba sin ningún aviso, en silencio, sin que nadie se enterara. 'ruta'
// usa el mismo mapa de deep links que ya entiende socio_dashboard_page.dart
// (_rutaATabIndex) para abrir directo en Mi Cuenta al tocar la notificación.
async function enviarPushSocio(fcmToken, { titulo, cuerpo, ruta }) {
    if (!fcmToken) return false;
    try {
        await admin.messaging().send({
            notification: { title: titulo, body: cuerpo },
            data: { ruta },
            token: fcmToken,
        });
        return true;
    } catch (error) {
        logger.warn(`enviarPushSocio: no se pudo enviar a ${fcmToken}: ${error.message}`);
        return false;
    }
}

async function enviarWhatsappConTokenAdmin(idTokenAdmin, telefono, mensaje) {
    const limpio = limpiarTelefonoAr(telefono);
    if (!limpio) return false;
    try {
        const resp = await axios.post(
            'https://servicio-whatsapp-oqua.onrender.com/send-whatsapp',
            { phone: limpio, message: mensaje },
            { headers: { Authorization: `Bearer ${idTokenAdmin}` } }
        );
        return !!(resp.data && resp.data.success === true);
    } catch (error) {
        logger.warn(`recordatoriosDiarios: no se pudo enviar a ${limpio}: ${error.message}`);
        return false;
    }
}

// 🕐 Throttle: no reenvía el mismo aviso todos los días mientras la
// condición siga activa (p. ej. un socio con cuota impaga no recibe un
// WhatsApp diario, sólo cada `diasMinimos` días).
function throttleVencido(ahoraMs, timestamp, diasMinimos) {
    if (!timestamp) return true;
    const DIA_MS = 24 * 60 * 60 * 1000;
    return (ahoraMs - timestamp.toMillis()) >= diasMinimos * DIA_MS;
}

async function ejecutarRecordatoriosDiarios() {
    const db = admin.firestore();

    // 🔌 Interruptor general: mientras el cliente prueba el sistema no
    // conviene que salgan mensajes reales a socios de verdad. Por defecto
    // (documento inexistente o campo ausente) queda APAGADO — hay que
    // prenderlo a propósito desde Administración > Config. Fiscal >
    // WhatsApp. El botón de prueba manual respeta el mismo interruptor.
    const configSnap = await db.collection('configuraciones_fiscales').doc('whatsapp_reglas').get();
    const activos = configSnap.exists && configSnap.data().recordatoriosActivos === true;
    if (!activos) {
        logger.info('recordatoriosDiarios: desactivado por configuración, no se envía nada.');
        return { cuotas: 0, aptos: 0, reservas: 0, desactivado: true };
    }

    const idTokenAdmin = await obtenerIdTokenDeAdminActivo(db);
    const ahora = admin.firestore.Timestamp.now();
    const ahoraMs = ahora.toMillis();
    const DIA_MS = 24 * 60 * 60 * 1000;

    const resultado = { cuotas: 0, aptos: 0, reservas: 0 };

    // 1) CUOTAS PENDIENTES — se apoya en los mismos registros 'Pendiente'
    // que ya genera la liquidación mensual (liquidacion_cuotas_service.dart)
    // y que usa el cobro manual, así no se duplica la lógica de qué está
    // vencido. Un solo filtro de igualdad (estado) para no depender de un
    // índice compuesto; 'tipo' se filtra en memoria.
    const pendientesSnap = await db.collectionGroup('cuenta_corriente')
        .where('estado', '==', 'Pendiente')
        .get();

    const deudaPorSocio = new Map();
    for (const doc of pendientesSnap.docs) {
        const data = doc.data();
        if (data.tipo !== 'Cuota Mensual') continue;
        const socioRef = doc.ref.parent.parent;
        if (!socioRef) continue;
        const actual = deudaPorSocio.get(socioRef.id) || { ref: socioRef, total: 0, periodos: [] };
        actual.total += (data.monto || 0);
        if (data.periodo) actual.periodos.push(data.periodo);
        deudaPorSocio.set(socioRef.id, actual);
    }

    for (const [, deuda] of deudaPorSocio) {
        const socioSnap = await deuda.ref.get();
        if (!socioSnap.exists) continue;
        const socio = socioSnap.data();
        // 🚨 Antes esto exigía 'socio.telefono' para seguir, así que un
        // socio sin teléfono cargado (pero con la app instalada, con
        // fcmToken) no recibía NINGÚN recordatorio — ni WhatsApp (no podía)
        // ni push (ni se intentaba). WhatsApp y push ahora son intentos
        // independientes; sólo se saltea si el socio está inactivo.
        if (socio.activo === false) continue;
        if (!throttleVencido(ahoraMs, socio.ultimoRecordatorioCuota, 5)) continue;

        const mensaje = `Hola ${socio.nombre || ''}! 👋 Te recordamos que tenés una cuota social pendiente en OQUA Club por un total de $${deuda.total.toFixed(2)} (período/s: ${deuda.periodos.join(', ')}). Podés regularizarla en recepción o por Mercado Pago. ¡Gracias!`;

        let enviado = false;
        if (socio.telefono) {
            enviado = await enviarWhatsappConTokenAdmin(idTokenAdmin, socio.telefono, mensaje);
            await esperar(1200);
        }
        const pushOk = await enviarPushSocio(socio.fcmToken, {
            titulo: '💳 Cuota pendiente',
            cuerpo: `Tenés una cuota pendiente de $${deuda.total.toFixed(2)} (${deuda.periodos.join(', ')}).`,
            ruta: 'cuenta_corriente',
        });
        enviado = enviado || pushOk;

        if (enviado) {
            await deuda.ref.update({ ultimoRecordatorioCuota: ahora });
            resultado.cuotas++;
        }
    }

    // 2) APTO MÉDICO VENCIDO O POR VENCER (próximos 15 días) — un solo
    // filtro de rango (vencimientoAptoMedico) para que Firestore lo indexe
    // automáticamente; 'activo' se filtra en memoria.
    const en15Dias = admin.firestore.Timestamp.fromMillis(ahoraMs + 15 * DIA_MS);
    const aptosSnap = await db.collection('socios')
        .where('vencimientoAptoMedico', '<=', en15Dias)
        .get();

    for (const doc of aptosSnap.docs) {
        const socio = doc.data();
        if (socio.activo === false || !socio.telefono || !socio.vencimientoAptoMedico) continue;
        if (!throttleVencido(ahoraMs, socio.ultimoRecordatorioApto, 7)) continue;

        // 🚨 Antes comparaba el instante exacto (`vencimiento.getTime() < ahoraMs`):
        // como vencimientoAptoMedico se guarda a medianoche del día de
        // vencimiento, esto ya daba "vencido" desde las 00:00 de ESE MISMO
        // día (un día antes de lo real) — mismo bug que vencimientoVigente()
        // en el cliente Flutter. Se compara sólo por día calendario.
        const vencimiento = socio.vencimientoAptoMedico.toDate();
        const hoyInicio = new Date(ahoraMs);
        hoyInicio.setHours(0, 0, 0, 0);
        const vencimientoInicio = new Date(vencimiento);
        vencimientoInicio.setHours(0, 0, 0, 0);
        const yaVencido = vencimientoInicio.getTime() < hoyInicio.getTime();
        const fechaStr = vencimiento.toLocaleDateString('es-AR');
        const mensaje = yaVencido
            ? `Hola ${socio.nombre || ''}! 👋 Tu apto médico en OQUA Club venció el ${fechaStr}. Por tu seguridad, necesitamos que nos acerques uno actualizado para poder seguir practicando actividades.`
            : `Hola ${socio.nombre || ''}! 👋 Tu apto médico en OQUA Club vence el ${fechaStr}. Te pedimos que nos acerques uno actualizado antes de esa fecha.`;
        const ok = await enviarWhatsappConTokenAdmin(idTokenAdmin, socio.telefono, mensaje);
        if (ok) {
            await doc.ref.update({ ultimoRecordatorioApto: ahora });
            resultado.aptos++;
            await esperar(1200);
        }
    }

    // 3) RESERVAS DE CANCHA DE MAÑANA — recordatorio único por reserva
    // (marcado con 'recordatorioEnviado'), no un ping horario preciso.
    const inicioManana = new Date(ahoraMs + DIA_MS);
    inicioManana.setHours(0, 0, 0, 0);
    const finManana = new Date(inicioManana.getTime());
    finManana.setHours(23, 59, 59, 999);

    const reservasSnap = await db.collection('reservas_canchas')
        .where('fecha', '>=', admin.firestore.Timestamp.fromDate(inicioManana))
        .where('fecha', '<=', admin.firestore.Timestamp.fromDate(finManana))
        .get();

    for (const doc of reservasSnap.docs) {
        const reserva = doc.data();
        if (reserva.recordatorioEnviado === true) continue;

        let telefono = null;
        let nombre = reserva.nombreCliente || '';
        if (reserva.socioId) {
            const socioSnap = await db.collection('socios').doc(reserva.socioId).get();
            if (socioSnap.exists) {
                telefono = socioSnap.data().telefono;
                nombre = socioSnap.data().nombre || nombre;
            }
        }
        if (!telefono) continue;

        const mensaje = `Hola ${nombre}! 👋 Te recordamos tu turno mañana en OQUA Club: cancha ${reserva.cancha || ''} a las ${reserva.horaInicio}:00hs. ¡Te esperamos!`;
        const ok = await enviarWhatsappConTokenAdmin(idTokenAdmin, telefono, mensaje);
        if (ok) {
            await doc.ref.update({ recordatorioEnviado: true });
            resultado.reservas++;
            await esperar(1200);
        }
    }

    logger.info(`recordatoriosDiarios: cuotas=${resultado.cuotas}, aptos=${resultado.aptos}, reservas=${resultado.reservas}`);
    return resultado;
}

// ⏰ Corre todos los días a las 10:00 (hora Argentina).
exports.recordatoriosDiarios = onSchedule({
    schedule: '0 10 * * *',
    timeZone: 'America/Argentina/Buenos_Aires',
    timeoutSeconds: 540,
}, async (event) => {
    try {
        await ejecutarRecordatoriosDiarios();
    } catch (error) {
        logger.error(`recordatoriosDiarios falló: ${error.message}`);
    }
});

// 🧪 Disparo manual para que el admin pueda probarlo sin esperar al cron.
exports.enviarRecordatoriosManual = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    try {
        const resultado = await ejecutarRecordatoriosDiarios();
        return { success: true, ...resultado };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

// =========================================================================
// 🔁 TURNOS RECURRENTES DE CANCHA (pádel) — mismo día/hora/cancha todas las
// semanas, sin tener que reservar una por una. El turno fijo TIENE
// PRIORIDAD: en vez de reservar semana a semana y arriesgarse a perder el
// horario si alguien más lo toma antes, esto reserva el horario de las
// próximas HORIZONTE_SEMANAS por adelantado — así el horario queda
// bloqueado para cualquier otra reserva (self-service o de staff) igual
// que cualquier reserva normal, porque ES una reserva normal más (misma
// colección 'reservas_canchas', mismos documentos "slot" de
// reservas_canchas_slots que ya usa reserva_cancha_repository.dart). Un
// cron diario mantiene ese horizonte siempre ~8 semanas hacia adelante.
//
// ⚠️ Si justo antes de crear el turno fijo ya había una reserva de otra
// persona en alguna de esas semanas (alguien reservó esa fecha puntual
// antes de que existiera el turno fijo), esa semana puntual NO se pisa ni
// se cancela sola — eso requeriría cancelar automáticamente la reserva
// confirmada (y tal vez ya cobrada) de otro socio, lo cual no es seguro
// hacer sin que alguien del staff lo decida. Esa semana queda marcada como
// conflicto para resolver a mano; las demás semanas sí quedan bloqueadas.
// =========================================================================

const HORIZONTE_SEMANAS_TURNO_FIJO = 8;

function _fechaIdStrCancha(fecha) {
    return `${fecha.getFullYear()}-${fecha.getMonth() + 1}-${fecha.getDate()}`;
}

// 🚨 Mismo formato de id que reserva_cancha_repository.dart /
// reserva_cancha_screen.dart (Dart interpola enteros sin ceros a la
// izquierda) — si no coincide exacto, el chequeo de solapamiento de la app
// no reconocería estos slots como ocupados.
function _idsOcurrenciaCancha({ fecha, cancha, horaInicio, duracionHoras }) {
    const fechaIdStr = _fechaIdStrCancha(fecha);
    const canchaLimpia = cancha.replace(/ /g, '');
    const slotIds = [];
    for (let h = horaInicio; h < horaInicio + duracionHoras; h++) {
        slotIds.push(`${fechaIdStr}_${canchaLimpia}_${h}hs`);
    }
    const reservaId = `${fechaIdStr}_${canchaLimpia}_${horaInicio}hs_duracion${duracionHoras}h`;
    return { reservaId, slotIds };
}

// Calcula el precio igual que reserva_cancha_screen.dart (tarifa base por
// hora + recargo de luz desde la hora configurada) — sin paleta/pelotas,
// que no tienen sentido fijos para un abono semanal.
async function _calcularPrecioCancha(db, { horaInicio, duracionHoras }) {
    const ajustesSnap = await db.collection('configuraciones_paddle').doc('ajustes_globales').get();
    const a = ajustesSnap.exists ? ajustesSnap.data() : {};
    const precioBase = a.precio_base_cancha ?? 4500;
    const horaInicioLuz = a.hora_inicio_luz ?? 20;
    const plusLuz = a.precio_adicional_luz ?? 1500;
    let total = 0;
    for (let h = horaInicio; h < horaInicio + duracionHoras; h++) {
        total += precioBase;
        if (h >= horaInicioLuz) total += plusLuz;
    }
    return total;
}

// Intenta crear UNA ocurrencia (una fecha puntual) del turno fijo, con la
// misma transacción atómica (chequeo de slots + reserva + slots, todo o
// nada) que ya usa el autoservicio normal. Devuelve si pudo o si hubo
// conflicto — no lanza para no cortar el loop de las demás semanas/turnos.
async function _crearOcurrenciaTurnoFijo(db, { turno, fecha }) {
    const { reservaId, slotIds } = _idsOcurrenciaCancha({
        fecha, cancha: turno.cancha, horaInicio: turno.horaInicio, duracionHoras: turno.duracionHoras,
    });
    const reservaRef = db.collection('reservas_canchas').doc(reservaId);
    const slotRefs = slotIds.map((id) => db.collection('reservas_canchas_slots').doc(id));
    const fechaUtc = new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate());

    // Fast path sin transacción: si ya existe (ya generada en una corrida
    // anterior, o coincide con el día en que se creó el turno), no hay
    // nada que hacer.
    if ((await reservaRef.get()).exists) return { creada: false, yaExistia: true };

    try {
        await db.runTransaction(async (tx) => {
            for (const slotRef of slotRefs) {
                const slotSnap = await tx.get(slotRef);
                if (slotSnap.exists) throw new Error('OCUPADO');
            }
            tx.set(reservaRef, {
                cancha: turno.cancha,
                nombreCliente: turno.nombreCliente,
                socioId: turno.socioId,
                fecha: admin.firestore.Timestamp.fromDate(fechaUtc),
                horaInicio: turno.horaInicio,
                duracionHoras: turno.duracionHoras,
                precio: turno.precio,
                metodoPago: 'Cuenta Corriente',
                estadoReserva: 'Confirmada',
                seña_abonada: 0,
                detalle_seña: '',
                turnoRecurrenteId: turno.id,
            });
            for (const slotRef of slotRefs) {
                tx.set(slotRef, { reservaId, cancha: turno.cancha, fecha: admin.firestore.Timestamp.fromDate(fechaUtc) });
            }
        });
        return { creada: true };
    } catch (error) {
        return { creada: false, conflicto: true };
    }
}

// Genera, para UN turno fijo activo, todas las ocurrencias que falten
// hasta el horizonte — se llama tanto al crear el turno (para no esperar
// al cron del día siguiente) como desde el cron diario (para ir corriendo
// el horizonte hacia adelante a medida que pasan las semanas).
async function _generarOcurrenciasDeUnTurno(db, turno) {
    const hoy = new Date();
    hoy.setHours(0, 0, 0, 0);
    // Próxima fecha que cae en turno.diaSemana (1=lunes..7=domingo, igual
    // que DateTime.weekday en Dart) a partir de hoy inclusive.
    const diffDias = (turno.diaSemana - (hoy.getDay() === 0 ? 7 : hoy.getDay()) + 7) % 7;
    const primeraFecha = new Date(hoy.getTime() + diffDias * 24 * 60 * 60 * 1000);

    let creadas = 0;
    let conflictos = 0;
    for (let semana = 0; semana < HORIZONTE_SEMANAS_TURNO_FIJO; semana++) {
        const fecha = new Date(primeraFecha.getTime() + semana * 7 * 24 * 60 * 60 * 1000);
        const resultado = await _crearOcurrenciaTurnoFijo(db, { turno, fecha });
        if (resultado.creada) creadas++;
        if (resultado.conflicto) conflictos++;
    }
    return { creadas, conflictos };
}

async function _crearTurnoRecurrenteCancha({ socioId, nombreCliente, cancha, diaSemana, horaInicio, duracionHoras, creadoPor }) {
    const db = admin.firestore();
    if (!cancha || !diaSemana || diaSemana < 1 || diaSemana > 7 || !horaInicio || !duracionHoras) {
        return { success: false, error: 'Faltan datos del turno fijo (cancha, día, horario o duración).' };
    }

    const precio = await _calcularPrecioCancha(db, { horaInicio, duracionHoras });

    const turnoRef = db.collection('turnos_recurrentes_canchas').doc();
    const turno = {
        id: turnoRef.id,
        socioId,
        nombreCliente,
        cancha,
        diaSemana,
        horaInicio,
        duracionHoras,
        precio,
        activo: true,
        creadoPor,
        creadoEl: admin.firestore.FieldValue.serverTimestamp(),
    };
    await turnoRef.set(turno);

    const { creadas, conflictos } = await _generarOcurrenciasDeUnTurno(db, turno);

    return {
        success: true,
        turnoId: turnoRef.id,
        ocurrenciasCreadas: creadas,
        conflictos,
    };
}

// Staff: asigna un turno fijo a un socio puntual (elegido en el panel de
// canchas) — mismo caso de uso que un "abono" arreglado en el mostrador.
exports.crearTurnoRecurrenteCanchaStaff = functions.https.onCall(async (data, context) => {
    await requireStaffOperativo(context);
    try {
        const { socioId, nombreCliente, cancha, diaSemana, horaInicio, duracionHoras } = data;
        if (!socioId) return { success: false, error: 'Falta elegir el socio.' };
        return await _crearTurnoRecurrenteCancha({
            socioId, nombreCliente, cancha, diaSemana, horaInicio, duracionHoras, creadoPor: context.auth.uid,
        });
    } catch (error) {
        return { success: false, error: error.message };
    }
});

// Self-service: el socio arma su propio turno fijo desde la app — igual
// criterio de resolución de identidad que crearCobroMercadoPagoSocio (el
// id del doc 'socios/{id}' no es el uid de Auth).
exports.crearTurnoRecurrenteCanchaSocio = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Necesitás iniciar sesión.');
    }
    const db = admin.firestore();
    try {
        const querySocio = await db.collection('socios')
            .where('usuarioUid', '==', context.auth.uid)
            .limit(1)
            .get();
        if (querySocio.empty) return { success: false, error: 'No encontramos tu ficha de socio.' };
        const socioDoc = querySocio.docs[0];
        const nombreCliente = `${socioDoc.data().nombre || ''} ${socioDoc.data().apellido || ''}`.trim() || 'Socio';

        const { cancha, diaSemana, horaInicio, duracionHoras } = data;
        return await _crearTurnoRecurrenteCancha({
            socioId: socioDoc.id, nombreCliente, cancha, diaSemana, horaInicio, duracionHoras, creadoPor: context.auth.uid,
        });
    } catch (error) {
        return { success: false, error: error.message };
    }
});

// Cancela el turno fijo y libera las semanas futuras que todavía no
// pasaron (si no se borraran esas ocurrencias, el horario seguiría
// bloqueado para siempre aunque el turno ya esté dado de baja).
exports.cancelarTurnoRecurrenteCancha = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Necesitás iniciar sesión.');
    }
    try {
        const { turnoId } = data;
        if (!turnoId) return { success: false, error: 'Falta el id del turno.' };
        const db = admin.firestore();
        const turnoRef = db.collection('turnos_recurrentes_canchas').doc(turnoId);
        const turnoSnap = await turnoRef.get();
        if (!turnoSnap.exists) return { success: false, error: 'No se encontró el turno fijo.' };
        const turno = turnoSnap.data();

        // Staff puede cancelar cualquiera; el socio sólo el suyo propio.
        let esStaff = true;
        try {
            await requireStaffOperativo(context);
        } catch {
            esStaff = false;
        }
        if (!esStaff) {
            const querySocio = await db.collection('socios')
                .where('usuarioUid', '==', context.auth.uid)
                .limit(1)
                .get();
            if (querySocio.empty || querySocio.docs[0].id !== turno.socioId) {
                throw new functions.https.HttpsError('permission-denied', 'Ese turno fijo no te pertenece.');
            }
        }

        await turnoRef.update({ activo: false });

        const hoy = new Date();
        hoy.setHours(0, 0, 0, 0);
        const futurasSnap = await db.collection('reservas_canchas')
            .where('turnoRecurrenteId', '==', turnoId)
            .where('fecha', '>=', admin.firestore.Timestamp.fromDate(hoy))
            .get();

        const batch = db.batch();
        let liberadas = 0;
        for (const doc of futurasSnap.docs) {
            const r = doc.data();
            const { slotIds } = _idsOcurrenciaCancha({
                fecha: r.fecha.toDate(), cancha: r.cancha, horaInicio: r.horaInicio, duracionHoras: r.duracionHoras,
            });
            batch.delete(doc.ref);
            for (const slotId of slotIds) batch.delete(db.collection('reservas_canchas_slots').doc(slotId));
            liberadas++;
        }
        await batch.commit();

        return { success: true, semanasLiberadas: liberadas };
    } catch (error) {
        if (error instanceof functions.https.HttpsError) throw error;
        return { success: false, error: error.message };
    }
});

// ⏰ Mantiene el horizonte de los turnos fijos activos siempre ~8 semanas
// hacia adelante — corre después del recordatorio diario para no competir
// por los mismos documentos a la misma hora exacta.
exports.generarOcurrenciasTurnosFijosCancha = onSchedule({
    schedule: '15 10 * * *',
    timeZone: 'America/Argentina/Buenos_Aires',
    timeoutSeconds: 540,
}, async () => {
    const db = admin.firestore();
    const turnosSnap = await db.collection('turnos_recurrentes_canchas').where('activo', '==', true).get();
    let totalCreadas = 0;
    let totalConflictos = 0;
    for (const doc of turnosSnap.docs) {
        const { creadas, conflictos } = await _generarOcurrenciasDeUnTurno(db, doc.data());
        totalCreadas += creadas;
        totalConflictos += conflictos;
    }
    logger.info(`generarOcurrenciasTurnosFijosCancha: turnos=${turnosSnap.size}, ocurrenciasCreadas=${totalCreadas}, conflictos=${totalConflictos}`);
});

// =========================================================================
// 🌐 DISPONIBILIDAD PÚBLICA DE PÁDEL — para mostrar en el sitio web
// (visitante anónimo, sin login) algo como "hoy quedan 6 turnos libres".
// Sólo devuelve conteos agregados, nunca nombres ni datos de socios — por
// eso es un endpoint HTTP sin autenticación (CORS abierto), a diferencia
// de todo lo demás en este archivo. No incluye andariveles (natatorio):
// ahí el cupo de un horario recién se fija con la PRIMERA reserva (depende
// de la categoría elegida), así que un horario sin reservas todavía no
// tiene una capacidad conocida de antemano — mostrar un número ahí sería
// inventarlo.
async function _disponibilidadPadelDia(db, fecha, { horaApertura, horaCierre, numCanchas }) {
    const inicioDia = new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate());
    const finDia = new Date(inicioDia.getTime() + 24 * 60 * 60 * 1000);

    const reservasSnap = await db.collection('reservas_canchas')
        .where('fecha', '>=', admin.firestore.Timestamp.fromDate(inicioDia))
        .where('fecha', '<', admin.firestore.Timestamp.fromDate(finDia))
        .get();

    let horasOcupadas = 0;
    for (const doc of reservasSnap.docs) {
        horasOcupadas += Number(doc.data().duracionHoras) || 1;
    }

    const capacidadTotal = Math.max(0, horaCierre - horaApertura) * numCanchas;
    const libres = Math.max(0, capacidadTotal - horasOcupadas);
    return { fecha: _fechaIdStrCancha(fecha), libres, capacidadTotal };
}

exports.obtenerDisponibilidadPublicaPadel = functions.https.onRequest(async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');
    if (req.method === 'OPTIONS') {
        res.set('Access-Control-Allow-Methods', 'GET');
        res.status(204).send('');
        return;
    }
    try {
        const db = admin.firestore();
        const ajustesSnap = await db.collection('configuraciones_paddle').doc('ajustes_globales').get();
        const horaApertura = (ajustesSnap.data()?.hora_apertura) ?? 8;
        const horaCierre = (ajustesSnap.data()?.hora_cierre) ?? 23;

        const canchasSnap = await db.collection('configuracion_paddle').doc('canchas').get();
        const listaCanchas = canchasSnap.data()?.lista || [];
        const numCanchas = listaCanchas.length || 1;

        const hoy = new Date();
        const manana = new Date(hoy.getTime() + 24 * 60 * 60 * 1000);

        const [disponibilidadHoy, disponibilidadManana] = await Promise.all([
            _disponibilidadPadelDia(db, hoy, { horaApertura, horaCierre, numCanchas }),
            _disponibilidadPadelDia(db, manana, { horaApertura, horaCierre, numCanchas }),
        ]);

        // Cache corto: evita que un pico de visitas al sitio le pegue a
        // Firestore en cada carga de página — 5 minutos es suficiente
        // frescura para un dato que es "a título informativo".
        res.set('Cache-Control', 'public, max-age=300');
        res.status(200).json({ hoy: disponibilidadHoy, manana: disponibilidadManana });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// =========================================================================
// 🎟️ PASES DIGITALES (Apple Wallet / Google Wallet) — SÓLO ESTRUCTURA.
//
// Generar un .pkpass real (Apple Wallet) requiere firmarlo con un
// certificado de un Apple Developer Program (pago, de Apple) emitido para
// este proyecto; un pase de Google Wallet requiere habilitar la Google
// Wallet API y un "issuer account" en Google Pay & Wallet Console. Ninguna
// de esas dos cosas existe todavía para OQUA, así que esta función NO
// genera ningún pase real: valida permisos, dibuja el `document.data` del
// pase (lo mismo que necesitaría el generador real) y lo deja grabado en
// Firestore con estado 'pendiente_configuracion' para no perder la
// solicitud. El día que se consigan esas credenciales, sólo hay que
// reemplazar el bloque "TODO" de abajo por la llamada real al SDK/API de
// Apple o Google (passkit-generator / @walletpass o la Google Wallet
// REST API) — el resto (auth, datos del pase, registro en Firestore) ya
// queda armado.
exports.generarPaseWallet = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Necesitás iniciar sesión para generar tu pase.'
        );
    }

    const db = admin.firestore();
    const socioId = data?.socioId;
    if (!socioId) {
        throw new functions.https.HttpsError('invalid-argument', 'Falta socioId.');
    }

    const socioDoc = await db.collection('socios').doc(socioId).get();
    if (!socioDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'No se encontró ese socio.');
    }
    const socio = socioDoc.data();

    // Sólo el propio socio (dueño del pase) o staff pueden pedirlo.
    const esElPropioSocio = socio.usuarioUid === context.auth.uid;
    if (!esElPropioSocio) {
        await requireAdmin(context);
    }

    // 📄 Lo que necesitaría el pase real — nombre, número de socio, vigencia
    // de la cuota/matrícula (mismo criterio de 'vencimientoVigente' que ya
    // usa la app) y el tipo de pase pedido.
    const tipoPase = data?.tipo === 'google' ? 'google' : 'apple';
    const datosPase = {
        socioId,
        tipoPase,
        nombre: socio.nombre || '',
        numeroSocio: socio.numeroSocio || socioId,
        matriculaAlDia: socio.matriculaAlDia === true,
        estado: 'pendiente_configuracion',
        solicitadoEn: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('pases_digitales').doc(socioId).set(datosPase, { merge: true });

    // 🔧 TODO (cuando haya credenciales de Apple/Google): generar acá el
    // .pkpass firmado (Apple) o el JWT del "Add to Google Wallet" (Google),
    // subirlo a Storage y devolver su URL en vez de este mensaje.
    return {
        success: false,
        configurado: false,
        mensaje:
            'Los pases digitales todavía no están habilitados (falta la cuenta ' +
            'de Apple Developer / Google Wallet). Tu pedido quedó registrado.',
    };
});