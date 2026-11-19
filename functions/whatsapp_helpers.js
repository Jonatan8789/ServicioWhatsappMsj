// 📲 Helpers compartidos para mandar WhatsApp real al mismo microservicio
// propio (servicio-whatsapp-oqua.onrender.com, Baileys/WhatsApp Web) que ya
// usan notificarWhatsappSocio y recordatoriosDiarios en index.js. Se
// extrajeron acá para que los triggers nuevos de notificaciones_whatsapp_padel.js
// (clases, turnos fijos, partido abierto, recibo de pago) los puedan reusar
// sin duplicar esta lógica ni seguir engordando index.js.
const admin = require('firebase-admin');
const axios = require('axios');
const logger = require('firebase-functions/logger');

// 🚨 El bridge de WhatsApp (server.js, en Render) exige un ID token de
// Firebase de un usuario con rol 'admin' en /usuarios/{uid} para
// /send-whatsapp. Para disparar un WhatsApp desde un trigger de servidor
// (sin que haya ningún socio ni staff "llamando" en ese momento) hace falta
// "tomar prestado" un token de un admin activo — mismo mecanismo que ya usa
// notificarWhatsappSocio (intercambio de un custom token con la Web API Key
// pública del proyecto, la misma que ya viaja embebida en el bundle de
// Flutter Web en lib/firebase_options.dart, no es un secreto).
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

function limpiarTelefonoAr(telefono) {
    let limpio = (telefono || '').toString().replace(/\D/g, '');
    if (!limpio) return '';
    if (limpio.startsWith('0')) limpio = limpio.substring(1);
    if (limpio.startsWith('15')) limpio = limpio.substring(2);
    if (!limpio.startsWith('54')) limpio = `549${limpio}`;
    return limpio;
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
        logger.warn(`enviarWhatsappConTokenAdmin: no se pudo enviar a ${limpio}: ${error.message}`);
        return false;
    }
}

module.exports = {
    obtenerIdTokenDeAdminActivo,
    limpiarTelefonoAr,
    enviarWhatsappConTokenAdmin,
};
