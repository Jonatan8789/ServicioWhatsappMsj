const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

setGlobalOptions({ maxInstances: 10 });

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const Afip = require('@afipsdk/afip.js');
const axios = require('axios'); // Para llamados HTTPS a Mercado Pago

if (!admin.apps.length) {
    admin.initializeApp();
}

// =========================================================================
// 1. EMISIÓN DE FACTURA ELECTRÓNICA (POS)
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
            'CantReg': 1, 
            'PtoVta': ptoVenta, 
            'CbteTipo': cbteTipo, 
            'Concepto': 1, 
            'DocTipo': data.socioDni ? 96 : 99, 
            'DocNro': data.socioDni ? parseInt(data.socioDni) : 0, 
            'CbteDesde': 1, 
            'CbteHasta': 1, 
            'CbteFch': fecha, 
            'ImpTotal': parseFloat(data.total), 
            'ImpTotConc': 0, 
            'ImpNeto': parseFloat(data.total), 
            'ImpOpEx': 0, 
            'ImpIVA': 0, 
            'ImpTrib': 0, 
            'MonId': 'PES', 
            'MonCotiz': 1 
        };

        const lastCbte = await afip.ElectronicBilling.getLastVoucher(reqData.PtoVta, reqData.CbteTipo); 
        reqData.CbteDesde = lastCbte + 1; 
        reqData.CbteHasta = lastCbte + 1; 

        const res = await afip.ElectronicBilling.createVoucher(reqData); 

        return { 
            'success': true, 
            'cae': res.CAE, 
            'vencimientoCae': res.CAEFchVto, 
            'nroFactura': reqData.CbteDesde, 
            'puntoVenta': reqData.PtoVta, 
            'tipoComprobante': cbteTipo 
        };

    } catch (error) {
        console.error("Error ARCA fiscal:", error); 
        return { 'success': false, 'error': error.message }; 
    }
});

// =========================================================================
// 2. EMISIÓN DE NOTAS DE CRÉDITO Y DÉBITO (AJUSTES FISCALES)
// =========================================================================
exports.emitirNotaCreditoDebitoArca = functions.https.onCall(async (data, context) => {
    const db = admin.firestore();

    try {
        const configDoc = await db.collection('configuraciones_fiscales').doc('arca_reglas').get();
        if (!configDoc.exists) {
            return { 'success': false, 'error': 'Falta configurar los parámetros fiscales.' };
        }

        const configFiscal = configDoc.data();
        const cuitClub = configFiscal.cuit;
        const ptoVenta = parseInt(data.puntoVenta ?? configFiscal.puntoVenta ?? 1);
        const esProduccion = configFiscal.modoProduccion ?? false;
        
        const cbteAsociadoTipo = parseInt(data.comprobanteAsociadoTipo ?? 11);
        const cbteAsociadoNro = parseInt(data.comprobanteAsociadoNro);
        const esCredito = data.esCredito ?? true;

        let cbteAjusteTipo = 13; 
        if (cbteAsociadoTipo === 1) {
            cbteAjusteTipo = esCredito ? 3 : 2;
        } else if (cbteAsociadoTipo === 6) {
            cbteAjusteTipo = esCredito ? 8 : 7;
        } else if (cbteAsociadoTipo === 11) {
            cbteAjusteTipo = esCredito ? 13 : 12;
        }

        const afip = new Afip({ 
            'CUIT': cuitClub, 
            'production': esProduccion, 
            'cert': 'certificados/club_arca.crt', 
            'key': 'certificados/club_arca.key' 
        });

        const fecha = new Date(Date.now() - 3 * 3600 * 1000).toISOString().split('T')[0].replace(/-/g, '');

        const reqData = {
            'CantReg': 1,
            'PtoVta': ptoVenta,
            'CbteTipo': cbteAjusteTipo,
            'Concepto': 1,
            'DocTipo': 99,
            'DocNro': 0,
            'CbteDesde': 1,
            'CbteHasta': 1,
            'CbteFch': fecha,
            'ImpTotal': parseFloat(data.monto),
            'ImpTotConc': 0,
            'ImpNeto': parseFloat(data.monto),
            'ImpOpEx': 0,
            'ImpIVA': 0,
            'ImpTrib': 0,
            'MonId': 'PES',
            'MonCotiz': 1,
            'CbtesAsoc': [
                {
                    'Tipo': cbteAsociadoTipo,
                    'PtoVta': ptoVenta,
                    'Nro': cbteAsociadoNro
                }
            ]
        };

        const lastCbte = await afip.ElectronicBilling.getLastVoucher(reqData.PtoVta, reqData.CbteTipo);
        reqData.CbteDesde = lastCbte + 1;
        reqData.CbteHasta = lastCbte + 1;

        const res = await afip.ElectronicBilling.createVoucher(reqData);

        return {
            'success': true,
            'cae': res.CAE,
            'vencimientoCae': res.CAEFchVto,
            'nroComprobante': reqData.CbteDesde,
            'tipoComprobante': cbteAjusteTipo
        };

    } catch (error) {
        console.error("Error ARCA NC/ND:", error);
        return { 'success': false, 'error': error.message };
    }
});

// =========================================================================
// 3. PRUEBA DE CONEXIÓN Y HANDSHAKE DESDE EL MENÚ DE CONFIGURACIÓN
// =========================================================================
exports.probarConexionArca = functions.https.onCall(async (data, context) => {
    try {
        const cuit = parseInt(data.cuit);
        const ptoVenta = parseInt(data.puntoVenta ?? 1);
        const esProduccion = data.modoProduccion ?? false;

        const afip = new Afip({ 
            'CUIT': cuit, 
            'production': esProduccion, 
            'cert': 'certificados/club_arca.crt', 
            'key': 'certificados/club_arca.key' 
        });

        const status = await afip.ElectronicBilling.getServerStatus();

        return {
            'success': true,
            'status': status.AppServer,
            'dbServer': status.DbServer,
            'authServer': status.AuthServer
        };
    } catch (error) {
        console.error("Error prueba conexion ARCA:", error);
        return { 'success': false, 'error': error.message };
    }
});

// =========================================================================
// 4. INTEGRACIÓN MERCADO PAGO (GENERACIÓN DE PREFERENCIA & WEBHOOK IPN)
// =========================================================================
exports.crearCobroMercadoPago = functions.https.onCall(async (data, context) => {
    try {
        const { monto, concepto, ventaId } = data;
        const db = admin.firestore();

        const configSnap = await db.collection('configuraciones_fiscales').doc('mp_reglas').get();
        if (!configSnap.exists) {
            return { success: false, error: "Falta configurar las credenciales de Mercado Pago en configuraciones_fiscales/mp_reglas." };
        }
        const accessToken = configSnap.data().accessToken;

        const response = await axios.post(
            'https://api.mercadopago.com/checkout/preferences',
            {
                items: [
                    {
                        title: concepto || 'Consumo Aqua & Paddle Club',
                        quantity: 1,
                        currency_id: 'ARS',
                        unit_price: parseFloat(monto),
                    }
                ],
                external_reference: ventaId,
                notification_url: `https://us-central1-${process.env.GCP_PROJECT || process.env.GCLOUD_PROJECT}.cloudfunctions.net/webhookMercadoPago`,
            },
            {
                headers: {
                    'Authorization': `Bearer ${accessToken}`,
                    'Content-Type': 'application/json',
                }
            }
        );

        return {
            success: true,
            initPoint: response.data.init_point,
            preferenceId: response.data.id,
        };
    } catch (error) {
        console.error("Error creando cobro MP:", error);
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
        console.error('Error Webhook MP:', error);
        res.status(500).send('Error');
    }
});