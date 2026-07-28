const express = require('express');
const cors = require('cors');
const QRCode = require('qrcode');
const qrcodeTerminal = require('qrcode-terminal');
const { makeWASocket, useMultiFileAuthState, DisconnectReason } = require('@whiskeysockets/baileys');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());

let sock = null;
let latestQrBase64 = null;
let isConnected = false;

const AUTH_FOLDER = path.join(__dirname, 'auth_info_baileys');

async function connectToWhatsApp() {
    const { state, saveCreds } = await useMultiFileAuthState(AUTH_FOLDER);

    sock = makeWASocket({
        auth: state,
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
            console.log('✅ WhatsApp Conectado correctamente');
            isConnected = true;
            latestQrBase64 = null;
        }

        if (connection === 'close') {
            isConnected = false;
            const shouldReconnect = (lastDisconnect?.error)?.output?.statusCode !== DisconnectReason.loggedOut;
            console.log('❌ Conexión cerrada. ¿Reconectar?:', shouldReconnect);
            if (shouldReconnect) {
                connectToWhatsApp();
            }
        }
    });
}

// 📌 ENDPOINT DE SALUD (Para el ping de UptimeRobot y evitar que Render se duerma)
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
        if (fs.existsSync(AUTH_FOLDER)) {
            fs.rmSync(AUTH_FOLDER, { recursive: true, force: true });
        }
        isConnected = false;
        latestQrBase64 = null;
        
        setTimeout(() => connectToWhatsApp(), 2000);

        res.json({ success: true, message: 'Sesión cerrada correctamente' });
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
        // Limpiamos estrictamente a solo números por seguridad
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

// Configuración de puerto compatible con Render (process.env.PORT) y entorno local (3000)
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🚀 Servidor ejecutándose en el puerto ${PORT}`);
    connectToWhatsApp();
});