import 'package:cloud_firestore/cloud_firestore.dart';
import 'reserva_cancha_model.dart';

/// Se lanza cuando, dentro de la transacción atómica, alguna de las horas
/// pedidas ya fue tomada por otra reserva (propia colisión de id exacto, o
/// un bloque de distinta duración que se solapa).
class HorarioOcupadoException implements Exception {
  final String message;
  HorarioOcupadoException([this.message = 'Ese horario ya fue reservado.']);
  @override
  String toString() => message;
}

List<DocumentReference<Map<String, dynamic>>> _slotRefsDeReserva(
  FirebaseFirestore firestore,
  ReservaCanchaModel reserva,
) {
  final fecha = reserva.fecha;
  final fechaIdStr = "${fecha.year}-${fecha.month}-${fecha.day}";
  final canchaLimpia = reserva.cancha.replaceAll(' ', '');
  return [
    for (
      int h = reserva.horaInicio;
      h < reserva.horaInicio + reserva.duracionHoras;
      h++
    )
      firestore
          .collection('reservas_canchas_slots')
          .doc('${fechaIdStr}_${canchaLimpia}_${h}hs'),
  ];
}

/// Crea una reserva de cancha garantizando, a nivel de Firestore, que dos
/// personas reservando al mismo tiempo no puedan quedarse las dos con el
/// mismo horario.
///
/// Antes cada pantalla (admin, app del socio) hacía un `get()` para
/// detectar solapamientos y recién después escribía la reserva con un
/// `set()` aparte: entre ese chequeo y esa escritura (típicamente al tocar
/// "Confirmar" casi al mismo tiempo desde dos dispositivos) no había ninguna
/// garantía atómica, así que dos reservas podían pasar el chequeo juntas y
/// terminar las dos "confirmadas" para la misma cancha/hora — o, si el id
/// coincidía exacto, la segunda directamente pisaba a la primera sin avisar
/// (se perdía la reserva y el cobro asociado). Ahora cada hora ocupada se
/// marca con un documento "slot" propio y todo (chequeo + reserva + slots)
/// se hace dentro de una única `runTransaction`: Firestore sólo deja
/// confirmar una de las dos si compiten por la misma hora.
Future<void> reservarCanchaAtomica({
  required FirebaseFirestore firestore,
  required ReservaCanchaModel reserva,
  Map<String, dynamic> datosExtra = const {},
}) async {
  final reservaRef = firestore
      .collection('reservas_canchas')
      .doc(reserva.id);
  final slotRefs = _slotRefsDeReserva(firestore, reserva);
  final fecha = reserva.fecha;
  final fechaUtc = DateTime(fecha.year, fecha.month, fecha.day);

  await firestore.runTransaction((transaction) async {
    // Todas las lecturas van antes que cualquier escritura (lo exige
    // Firestore dentro de una transacción).
    for (final slotRef in slotRefs) {
      final slotSnap = await transaction.get(slotRef);
      if (slotSnap.exists) {
        throw HorarioOcupadoException();
      }
    }

    final data = reserva.toFirestore();
    data.addAll(datosExtra);
    transaction.set(reservaRef, data);

    for (final slotRef in slotRefs) {
      transaction.set(slotRef, {
        'reservaId': reserva.id,
        'cancha': reserva.cancha,
        'fecha': Timestamp.fromDate(fechaUtc),
      });
    }
  });
}

/// Cancela/libera una reserva junto con sus horas ocupadas en un único
/// batch atómico. Si sólo se borrara el documento de `reservas_canchas` (lo
/// que hacía antes), los documentos de slot de esa reserva quedaban
/// huérfanos y esas horas se mostraban como ocupadas para siempre.
Future<void> cancelarReservaCanchaAtomica({
  required FirebaseFirestore firestore,
  required ReservaCanchaModel reserva,
}) async {
  final batch = firestore.batch();
  batch.delete(firestore.collection('reservas_canchas').doc(reserva.id));
  for (final slotRef in _slotRefsDeReserva(firestore, reserva)) {
    batch.delete(slotRef);
  }
  await batch.commit();
}
