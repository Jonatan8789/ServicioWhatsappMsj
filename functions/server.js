const express = require('express');
const cors = require('cors');
const QRCode = require('qrcode');
const qrcodeTerminal = require('qrcode-terminal');
const { makeWASocket, DisconnectReason, initAuthCreds, BufferJSON } = require('@whiskeysockets/baileys');
const admin = require('firebase-admin');

const app = express();
app.use(cors());
app.use(express.json());

// 1. Inicialización de Firebase Admin en Render
if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert({
            projectId: process.env.FIREBASE_PROJECT_ID,
            clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
            privateKey: process.env.FIREBASE_PRIVATE_KEY 
                ? process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n') 
                : undefined,
        })
    });
}
const db = admin.firestore();

let sock = null;
let latestQrBase64 = null;
let isConnected = false;

// 2. Auth State Persistente en Firestore
async function useFirestoreAuthState(docId = 'session_credentials') {
    const docRef = db.collection('whatsapp_session').doc(docId);
    const doc = await docRef.get();

    let creds;
    if (doc.exists && doc.data().creds) {
        creds = JSON.parse(JSON.stringify(doc.data().creds), BufferJSON.reviver);
    } else {
        creds = initAuthCreds();
    }

    return {
        state: {
            creds,
            keys: {
                get: async (type, ids) => {
                    const data = {};
                    await Promise.all(
                        ids.map(async (id) => {
                            const itemDoc = await docRef.collection(type).doc(id).get();
                            if (itemDoc.exists && itemDoc.data().value) {
                                data[id] = JSON.parse(JSON.stringify(itemDoc.data().value), BufferJSON.reviver);
                            }
                        })
                    );
                    return data;
                },
                set: async (data) => {
                    const batch = db.batch();
                    for (const category in data) {
                        for (const id in data[category]) {
                            const value = data[category][id];
                            const itemRef = docRef.collection(category).doc(id);
                            if (value) {
                                batch.set(itemRef, { value: JSON.parse(JSON.stringify(value, BufferJSON.replacer)) });
                            } else {
                                batch.delete(itemRef);
                            }
                        }
                    }
                    await batch.commit();
                }
            }
        },
        saveCreds: async () => {
            await docRef.set({
                creds: JSON.parse(JSON.stringify(creds, BufferJSON.replacer)),
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
        },
        clearState: async () => {
            await docRef.delete();
        }
    };
}

// 3. Conexión de WhatsApp usando Firestore
async function connectToWhatsApp() {
    const { state, saveCreds, clearState } = await useFirestoreAuthState();

    sock = makeWASocket({
        auth: state,
        printQRInTerminal: false,
        connectTimeoutMs: 60000,
        defaultQueryTimeoutMs: 60000,
        keepAliveIntervalMs: 10000,
    });

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', async (update) => {
        const { connection, lastDisconnect, qr } = update;

        if (qr) {
            console.log('\n================ ESCANEA ESTE CÓDIGO QR ================');
            qrcodeTerminal.generate(qr, { small: true });
            console.log('========================================================\n');

            latestQrBase64 = await QRCode.toDataURL(qr);
            isConnected = false;
        }

        if (connection === 'open') {
            console.log('✅ WhatsApp Conectado correctamente y persistido en Firestore');
            isConnected = true;
            latestQrBase64 = null;
        }

        if (connection === 'close') {
            isConnected = false;
            const statusCode = (lastDisconnect?.error)?.output?.statusCode;
            const shouldReconnect = statusCode !== DisconnectReason.loggedOut;
            console.log('❌ Conexión cerrada. Status:', statusCode, '¿Reconectar?:', shouldReconnect);

            if (statusCode === DisconnectReason.loggedOut) {
                console.log('🔒 Sesión cerrada explícitamente. Limpiando credenciales en Firestore...');
                await clearState();
            }

            if (shouldReconnect) {
                setTimeout(() => connectToWhatsApp(), 3000);
            }
        }
    });
}

// 📌 ENDPOINT DE SALUD
app.get('/health', (req, res) => {
    res.status(200).send('OK - Backend Baileys Activo');
});

// 📌 ENDPOINT: Consultar estado actual
app.get('/status', (req, res) => {
    res.json({
        connected: isConnected,
        qr: latestQrBase64,
    });
});

// 📌 ENDPOINT: Visualizar QR en navegador web
app.get('/qr', (req, res) => {
    if (isConnected) {
        return res.send(`
            <div style="font-family: sans-serif; text-align: center; margin-top: 50px;">
                <h2>Dispositivo Conectado ✅</h2>
                <p>El servicio de WhatsApp se encuentra autenticado y operativo.</p>
            </div>
        `);
    }

    if (!latestQrBase64) {
        return res.send(`
            <div style="font-family: sans-serif; text-align: center; margin-top: 50px;">
                <h2>Generando Código QR...</h2>
                <p>Por favor, aguardá unos segundos y recargá la página.</p>
            </div>
        `);
    }

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
                    <img src="${latestQrBase64}" alt="Código QR" />
                </div>
            </body>
        </html>
    `);
});

// 📌 ENDPOINT: Cerrar sesión y desvincular
app.post('/logout', async (req, res) => {
    try {
        if (sock) {
            await sock.logout();
        }
        const { clearState } = await useFirestoreAuthState();
        await clearState();

        isConnected = false;
        latestQrBase64 = null;
        
        setTimeout(() => connectToWhatsApp(), 2000);

        res.json({ success: true, message: 'Sesión desvinculada y limpiada en Firestore correctamente' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// 📌 ENDPOINT: Enviar mensaje de WhatsApp
app.post('/send-whatsapp', async (req, res) => {
    const { phone, message } = req.body;
    if (!isConnected || !sock) {
        return res.status(500).json({ success: false, error: 'WhatsApp no está conectado' });
    }
    try {
        const cleanPhone = String(phone).replace(/\D/g, '');
        const jid = `${cleanPhone}@s.whatsapp.net`;
        
        await sock.sendMessage(jid, { text: message });
        console.log(`💬 Mensaje enviado exitosamente a: ${cleanPhone}`);
        res.json({ success: true });
    } catch (err) {
        console.error('Error enviando mensaje WhatsApp:', err);
        res.status(500).json({ success: false, error: err.message });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🚀 Servidor ejecutándose en el puerto ${PORT}`);
    connectToWhatsApp();
});

// Agregá esta línea al final de tu index.js:
const notificaciones = require('./notificaciones');

exports.notificarInscripcionTorneo = notificaciones.notificarInscripcionTorneo;
exports.notificarReservaCancha = notificaciones.notificarReservaCancha;