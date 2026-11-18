const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

// 🚨 Este archivo usaba la API v1 de firebase-functions
// (functions.firestore.document(...).onCreate(...)), incompatible con la
// versión instalada (firebase-functions ^7.3.2, que ya removió ese shim de
// compatibilidad) — por eso 'require' tiraba
// "functions.firestore.document is not a function" apenas se intentaba
// cargar este módulo, y nunca llegó a desplegarse. Migrado a la API v2
// (onDocumentCreated), la misma que ya usa index.js (onDocumentWritten).

// 🏆 1. Disparo automático al registrarse una pareja en un torneo
exports.notificarInscripcionTorneo = onDocumentCreated(
  "torneos/{torneoId}/parejas_inscriptas/{inscripcionId}",
  async (event) => {
    const data = event.data.data();
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
      // 🔗 Deep link: socio_dashboard_page.dart usa esto para saltar
      // directo a la pestaña de Torneos al tocar la notificación.
      data: { ruta: "torneos" },
      token: fcmToken,
    };

    try {
      await admin.messaging().send(message);
      console.log(`🔔 Notificación de torneo enviada a socio ID: ${jugadorId}`);
    } catch (error) {
      console.error("🚨 Error enviando notificación de torneo:", error);
    }
  },
);

// 🎾 2. Disparo automático al registrar una reserva de cancha
exports.notificarReservaCancha = onDocumentCreated(
  "ventas_pendientes/{reservaId}",
  async (event) => {
    const data = event.data.data();
    // 🚨 'ventas_pendientes.socio_id' es el UID de Firebase Auth (así lo
    // exige la regla de creación de esta colección, pensada para que el
    // propio socio pueda escribir su alta), NO el id del doc 'socios/{id}'
    // (que es un id de alta/migración distinto) — buscar con .doc(socioId)
    // directo nunca encontraba el socio real y la notificación no salía
    // nunca. Hay que resolverlo por el campo 'usuarioUid', igual que en el
    // resto de la app (ver reserva_cancha_screen.dart).
    const authUid = data.socio_id;

    if (!authUid) return null;

    const querySocio = await admin
      .firestore()
      .collection("socios")
      .where("usuarioUid", "==", authUid)
      .limit(1)
      .get();
    if (querySocio.empty) return null;
    const docSocio = querySocio.docs[0];

    const fcmToken = docSocio.data().fcmToken;
    if (!fcmToken) return null;

    const message = {
      notification: {
        title: "🎾 Turno Confirmado",
        body: `Tu reserva de cancha fue registrada exitosamente.`,
      },
      // 🔗 Deep link: salta directo a la pestaña de Turnos (pádel).
      data: { ruta: "reservas_canchas" },
      token: fcmToken,
    };

    try {
      await admin.messaging().send(message);
      console.log(`🔔 Notificación de turno enviada a socio ID: ${docSocio.id}`);
    } catch (error) {
      console.error("🚨 Error enviando notificación de turno:", error);
    }
  },
);