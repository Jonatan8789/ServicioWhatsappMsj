const functions = require("firebase-functions");
const admin = require("firebase-admin");

// 🏆 1. Disparo automático al registrarse una pareja en un torneo
exports.notificarInscripcionTorneo = functions.firestore
  .document("torneos/{torneoId}/parejas_inscriptas/{inscripcionId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const jugadorId = data.jugador1Id;

    if (!jugadorId) return null;

    const docSocio = await admin.firestore().collection("socios").doc(jugadorId).get();
    if (!docSocio.exists) return null;

    const fcmToken = docSocio.data().fcmToken;
    if (!fcmToken) return null;

    const message = {
      notification: {
        title: "🏆 Inscripción Confirmada",
        body: `Te inscribiste al torneo con ${data.jugador2Nombre}. ¡Muchos éxitos!`,
      },
      token: fcmToken,
    };

    try {
      await admin.messaging().send(message);
      console.log(`🔔 Notificación de torneo enviada a socio ID: ${jugadorId}`);
    } catch (error) {
      console.error("🚨 Error enviando notificación de torneo:", error);
    }
  });

// 🎾 2. Disparo automático al registrar una reserva de cancha
exports.notificarReservaCancha = functions.firestore
  .document("ventas_pendientes/{reservaId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const socioId = data.socio_id;

    if (!socioId) return null;

    const docSocio = await admin.firestore().collection("socios").doc(socioId).get();
    if (!docSocio.exists) return null;

    const fcmToken = docSocio.data().fcmToken;
    if (!fcmToken) return null;

    const message = {
      notification: {
        title: "🎾 Turno Confirmado",
        body: `Tu reserva de cancha fue registrada exitosamente.`,
      },
      token: fcmToken,
    };

    try {
      await admin.messaging().send(message);
      console.log(`🔔 Notificación de turno enviada a socio ID: ${socioId}`);
    } catch (error) {
      console.error("🚨 Error enviando notificación de turno:", error);
    }
  });