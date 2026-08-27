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

// 📌 ENDPOINT DE SALUD (Para el ping de UptimeRobot)
app.get('/health', (req, res) => {
    res.status(200).send('OK - Backend Baileys Activo');
});

// 📌 ENDPOINT 1: Consultar estado actual
app.get('/status', (req, res) => {
    res.json({
        connected: isConnected,
        qr: latestQrBase64,
    });
});

// 📌 ENDPOINT 2: Cerrar sesión y desvincular
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

// 📌 ENDPOINT 3: Enviar mensaje de WhatsApp
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