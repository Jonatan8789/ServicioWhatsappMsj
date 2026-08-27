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
    const procesados = await ejecutarSincronizacionPadelManager();
    return res.status(200).json({ exito: true, procesados });
  } catch (error) {
    return res.status(500).json({ exito: false, error: error.toString() });
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
exports.emitirFacturaArca = functions.https.onCall(async (data, context) => {
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

        const afip = new Afip({ 
            'CUIT': cuitClub, 
            'production': esProduccion, 
            'cert': 'certificados/club_arca.crt', 
            'key': 'certificados/club_arca.key' 
        });

        const fecha = new Date(Date.now() - 3 * 3600 * 1000).toISOString().split('T')[0].replace(/-/g, '');

        const reqData = { 
            'CantReg': 1, 'PtoVta': ptoVenta, 'CbteTipo': cbteTipo, 'Concepto': 1, 
            'DocTipo': data.socioDni ? 96 : 99, 'DocNro': data.socioDni ? parseInt(data.socioDni) : 0, 
            'CbteDesde': 1, 'CbteHasta': 1, 'CbteFch': fecha, 'ImpTotal': parseFloat(data.total), 
            'ImpTotConc': 0, 'ImpNeto': parseFloat(data.total), 'ImpOpEx': 0, 'ImpIVA': 0, 
            'ImpTrib': 0, 'MonId': 'PES', 'MonCotiz': 1 
        };

        const lastCbte = await afip.ElectronicBilling.getLastVoucher(reqData.PtoVta, reqData.CbteTipo); 
        reqData.CbteDesde = lastCbte + 1; 
        reqData.CbteHasta = lastCbte + 1; 

        const res = await afip.ElectronicBilling.createVoucher(reqData); 

        return { 
            'success': true, 'cae': res.CAE, 'vencimientoCae': res.CAEFchVto, 
            'nroFactura': reqData.CbteDesde, 'puntoVenta': reqData.PtoVta, 'tipoComprobante': cbteTipo 
        };
    } catch (error) {
        return { 'success': false, 'error': error.message }; 
    }
});

exports.emitirNotaCreditoDebitoArca = functions.https.onCall(async (data, context) => {
    const db = admin.firestore();
    try {
        const configDoc = await db.collection('configuraciones_fiscales').doc('arca_reglas').get();
        if (!configDoc.exists) return { 'success': false, 'error': 'Falta configurar los parámetros fiscales.' };

        const configFiscal = configDoc.data();
        const cuitClub = configFiscal.cuit;
        const ptoVenta = parseInt(data.puntoVenta ?? configFiscal.puntoVenta ?? 1);
        const esProduccion = configFiscal.modoProduccion ?? false;
        
        const cbteAsociadoTipo = parseInt(data.comprobanteAsociadoTipo ?? 11);
        const cbteAsociadoNro = parseInt(data.comprobanteAsociadoNro);
        const esCredito = data.esCredito ?? true;

        let cbteAjusteTipo = 13; 
        if (cbteAsociadoTipo === 1) cbteAjusteTipo = esCredito ? 3 : 2;
        else if (cbteAsociadoTipo === 6) cbteAjusteTipo = esCredito ? 8 : 7;
        else if (cbteAsociadoTipo === 11) cbteAjusteTipo = esCredito ? 13 : 12;

        const afip = new Afip({ 
            'CUIT': cuitClub, 'production': esProduccion, 
            'cert': 'certificados/club_arca.crt', 'key': 'certificados/club_arca.key' 
        });

        const fecha = new Date(Date.now() - 3 * 3600 * 1000).toISOString().split('T')[0].replace(/-/g, '');

        const reqData = {
            'CantReg': 1, 'PtoVta': ptoVenta, 'CbteTipo': cbteAjusteTipo, 'Concepto': 1, 
            'DocTipo': 99, 'DocNro': 0, 'CbteDesde': 1, 'CbteHasta': 1, 'CbteFch': fecha, 
            'ImpTotal': parseFloat(data.monto), 'ImpTotConc': 0, 'ImpNeto': parseFloat(data.monto), 
            'ImpOpEx': 0, 'ImpIVA': 0, 'ImpTrib': 0, 'MonId': 'PES', 'MonCotiz': 1, 
            'CbtesAsoc': [{'Tipo': cbteAsociadoTipo, 'PtoVta': ptoVenta, 'Nro': cbteAsociadoNro}]
        };

        const lastCbte = await afip.ElectronicBilling.getLastVoucher(reqData.PtoVta, reqData.CbteTipo);
        reqData.CbteDesde = lastCbte + 1;
        reqData.CbteHasta = lastCbte + 1;

        const res = await afip.ElectronicBilling.createVoucher(reqData);

        return {
            'success': true, 'cae': res.CAE, 'vencimientoCae': res.CAEFchVto, 
            'nroComprobante': reqData.CbteDesde, 'tipoComprobante': cbteAjusteTipo
        };
    } catch (error) {
        return { 'success': false, 'error': error.message };
    }
});

exports.probarConexionArca = functions.https.onCall(async (data, context) => {
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
    try {
        const { monto, concepto, ventaId } = data;
        const db = admin.firestore();
        const configSnap = await db.collection('configuraciones_fiscales').doc('mp_reglas').get();
        if (!configSnap.exists) return { success: false, error: "Falta configurar credenciales MP." };
        const accessToken = configSnap.data().accessToken;

        const response = await axios.post(
            'https://api.mercadopago.com/checkout/preferences',
            {
                items: [{ title: concepto || 'Consumo Aqua & Paddle Club', quantity: 1, currency_id: 'ARS', unit_price: parseFloat(monto) }],
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
                    await db.collection('ventas_buffet').doc(ventaId).update({
                        estadoPagoMP: 'Aprobado',
                        medio_pago: 'Mercado Pago (QR)',
                        mpPaymentId: paymentId,
                        fechaPagoMP: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
            }
        }
        res.status(200).send('OK');
    } catch (error) {
        res.status(500).send('Error');
    }
});

const express = require('express');
const QRCode = require('qrcode');
const app = express();

let qrCodeString = ''; // Almacenará el último código QR generado

// 📌 1. Escuchar el evento del QR según la librería que uses:

// Si usás 'whatsapp-web.js':
client.on('qr', (qr) => {
    qrCodeString = qr;
    console.log('⚡ Nuevo QR generado.');
});

// Si usás '@whiskeysockets/baileys':
// sock.ev.on('connection.update', (update) => {
//     const { qr } = update;
//     if (qr) qrCodeString = qr;
// });


// 📌 2. Endpoint Web para visualizar el QR desde el navegador
app.get('/qr', async (req, res) => {
  if (!qrCodeString) {
    return res.send(`
      <div style="font-family: sans-serif; text-align: center; margin-top: 50px;">
        <h2>Dispositivo Conectado o Esperando QR...</h2>
        <p>Si el servicio ya está autenticado, no requiere escanear un nuevo código.</p>
      </div>
    `);
  }

  try {
    const qrImageUrl = await QRCode.toDataURL(qrCodeString);
    res.send(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>Vincular WhatsApp - OQUA Club</title>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { font-family: system-ui, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background-color: #f8fafc; }
            .card { background: white; padding: 2rem; border-radius: 1rem; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); text-align: center; max-width: 360px; }
            img { width: 100%; max-width: 280px; height: auto; border-radius: 0.5rem; }
            p { color: #64748b; font-size: 0.9rem; }
          </style>
        </head>
        <body>
          <div class="card">
            <h2 style="color: #0f172a; margin-bottom: 0.5rem;">Vincular WhatsApp</h2>
            <p>Escaneá con la cámara desde <b>WhatsApp > Dispositivos vinculados</b></p>
            <img src="${qrImageUrl}" alt="Código QR" />
          </div>
        </body>
      </html>
    `);
  } catch (err) {
    res.status(500).send('Error al generar la imagen del QR');
  }
});