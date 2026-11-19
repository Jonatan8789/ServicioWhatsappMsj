// 📲 Notificaciones por WhatsApp de eventos de pádel (Fase 5) — clase
// confirmada, partido abierto (alguien se une / se completa el cupo) y
// aviso de recibo cuando Mercado Pago aprueba un pago. El turno fijo
// confirmado NO vive acá: se dispara directo dentro de
// _crearTurnoRecurrenteCancha (index.js), porque ahí ya se tiene todo el
// contexto a mano sin necesitar un trigger de Firestore.
//
// Todos gateados por su propio interruptor en
// configuraciones_fiscales/whatsapp_reglas (default apagado, mismo
// criterio de seguridad que 'recordatoriosActivos') para no mandar
// WhatsApp real mientras se prueba el sistema.
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const { obtenerIdTokenDeAdminActivo, enviarWhatsappConTokenAdmin } = require('./whatsapp_helpers');

if (!admin.apps.length) {
    admin.initializeApp();
}

function _fechaCortaStr(timestamp) {
    if (!timestamp) return '';
    const f = timestamp.toDate();
    return `${f.getDate().toString().padStart(2, '0')}/${(f.getMonth() + 1).toString().padStart(2, '0')}/${f.getFullYear()}`;
}

async function _whatsappReglasActivo(db, campo) {
    const configSnap = await db.collection('configuraciones_fiscales').doc('whatsapp_reglas').get();
    return configSnap.exists && configSnap.data()[campo] === true;
}

// 🎾 1. Inscripción a clase confirmada — dispara tanto con una inscripción
// directa como con una promoción desde la lista de espera (ambas hacen
// crecer 'inscriptosIds'), sin tener que repetir el envío en cada lugar
// del código que puede hacer crecer ese array (inscribirseAClasePadelAtomica,
// cancelarInscripcionClasePadelAtomica/Socio).
exports.notificarInscripcionClasePadel = onDocumentUpdated('clases_padel/{claseId}', async (event) => {
    const antes = event.data.before.data();
    const despues = event.data.after.data();
    const idsAntes = antes.inscriptosIds || [];
    const idsDespues = despues.inscriptosIds || [];
    if (idsDespues.length <= idsAntes.length) return;
    const nuevoSocioId = idsDespues[idsDespues.length - 1];
    if (idsAntes.includes(nuevoSocioId)) return;

    const db = admin.firestore();
    try {
        if (!(await _whatsappReglasActivo(db, 'notifClasesPadelActivo'))) return;

        const socioSnap = await db.collection('socios').doc(nuevoSocioId).get();
        const telefono = socioSnap.exists ? socioSnap.data().telefono : null;
        if (!telefono) return;

        const mensaje =
            `🎾 *¡Anotado en la clase!*\n\n` +
            `Quedaste anotado en *${despues.nombre}* con *${despues.profesorNombre}* ` +
            `el *${_fechaCortaStr(despues.fecha)}* a las *${despues.horaInicio}:00hs* en *${despues.cancha}*.`;

        const idTokenAdmin = await obtenerIdTokenDeAdminActivo(db);
        await enviarWhatsappConTokenAdmin(idTokenAdmin, telefono, mensaje);
    } catch (error) {
        logger.warn(`notificarInscripcionClasePadel: no se pudo enviar: ${error.message}`);
    }
});

// 🎾 2. Partido abierto — alguien se une (avisa al que se une, no al
// organizador que ya sabe) y cupo completo (avisa a los 4 jugadores).
exports.notificarEventosPartidoAbierto = onDocumentUpdated('partidos_abiertos/{partidoId}', async (event) => {
    const antes = event.data.before.data();
    const despues = event.data.after.data();

    const idsAntes = antes.jugadoresIds || [];
    const idsDespues = despues.jugadoresIds || [];
    const seCompleto = antes.estado !== 'Completo' && despues.estado === 'Completo';
    const nuevoJugadorId = idsDespues.length > idsAntes.length ? idsDespues[idsDespues.length - 1] : null;
    if (!nuevoJugadorId && !seCompleto) return;

    const db = admin.firestore();
    try {
        if (!(await _whatsappReglasActivo(db, 'notifPartidoAbiertoActivo'))) return;

        const detalleTurno = `*${despues.cancha}* el *${_fechaCortaStr(despues.fecha)}* a las *${despues.horaInicio}:00hs*`;
        const idTokenAdmin = await obtenerIdTokenDeAdminActivo(db);

        async function enviarA(socioId, mensaje) {
            const socioSnap = await db.collection('socios').doc(socioId).get();
            const telefono = socioSnap.exists ? socioSnap.data().telefono : null;
            if (!telefono) return;
            await enviarWhatsappConTokenAdmin(idTokenAdmin, telefono, mensaje);
        }

        if (nuevoJugadorId && nuevoJugadorId !== despues.creadoPor) {
            await enviarA(
                nuevoJugadorId,
                `🎾 *¡Te uniste al Partido Abierto!*\n\nQuedaste anotado para jugar en ${detalleTurno}.`
            );
        }

        if (seCompleto) {
            const mensajeCompleto = `🎾 *¡Partido completo!*\n\nYa son los 4 jugadores para ${detalleTurno}. ¡Nos vemos en la cancha!`;
            await Promise.all(idsDespues.map((id) => enviarA(id, mensajeCompleto)));
        }
    } catch (error) {
        logger.warn(`notificarEventosPartidoAbierto: no se pudo enviar: ${error.message}`);
    }
});

// 🧾 3. Aviso de recibo cuando Mercado Pago aprueba un pago. Sólo cubre
// pagos SELF-SERVICE (el propio socio pagando desde su dashboard): ahí
// 'creadoPor' es el auth.uid del socio que paga (ver
// crearCobroMercadoPagoSocio). Si el cobro lo inició staff (POS,
// mostrador), 'creadoPor' es el uid del cajero/admin, no del socio — no hay
// forma segura de adivinar quién pagó sin leer un campo específico de cada
// tipo de comprobante, así que se omite en silencio en vez de notificar a
// la persona equivocada.
exports.avisarWhatsappPagoConfirmadoMP = onDocumentUpdated('mp_cobros_pendientes/{cobroId}', async (event) => {
    const antes = event.data.before.data();
    const despues = event.data.after.data();
    if (antes.estado === 'Aprobado' || despues.estado !== 'Aprobado') return;

    const db = admin.firestore();
    try {
        if (!(await _whatsappReglasActivo(db, 'notifPagoConfirmadoActivo'))) return;
        if (!despues.creadoPor) return;

        const socioSnap = await db.collection('socios')
            .where('usuarioUid', '==', despues.creadoPor)
            .limit(1)
            .get();
        if (socioSnap.empty) return;
        const telefono = socioSnap.docs[0].data().telefono;
        if (!telefono) return;

        const monto = Number(despues.monto) || 0;
        const mensaje =
            `🧾 *¡Pago recibido!*\n\n` +
            `Recibimos tu pago de *$${monto.toFixed(0)}*` +
            `${despues.concepto ? ` por ${despues.concepto}` : ''}. ¡Gracias!`;

        const idTokenAdmin = await obtenerIdTokenDeAdminActivo(db);
        await enviarWhatsappConTokenAdmin(idTokenAdmin, telefono, mensaje);
    } catch (error) {
        logger.warn(`avisarWhatsappPagoConfirmadoMP: no se pudo enviar: ${error.message}`);
    }
});
