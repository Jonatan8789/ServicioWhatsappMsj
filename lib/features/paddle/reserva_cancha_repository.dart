import 'package:cloud_firestore/cloud_firestore.dart';
import 'paddle_ids.dart';
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

/// Se lanza cuando no hay stock suficiente en `inventario_general` para
/// alguno de los ítems de Pro-Shop (paleta, pelotas) que se intentan vender
/// junto con la reserva.
class StockInsuficienteException implements Exception {
  final String productoNombre;
  final int stockDisponible;
  StockInsuficienteException(this.productoNombre, this.stockDisponible);
  @override
  String toString() =>
      'No hay stock suficiente de "$productoNombre" (quedan $stockDisponible).';
}

List<DocumentReference<Map<String, dynamic>>> _slotRefsDeReserva(
  FirebaseFirestore firestore,
  ReservaCanchaModel reserva,
) {
  return [
    for (final slotId in idsSlotsCancha(
      fecha: reserva.fecha,
      cancha: reserva.cancha,
      horaInicio: reserva.horaInicio,
      duracionHoras: reserva.duracionHoras,
    ))
      firestore.collection('reservas_canchas_slots').doc(slotId),
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

  final inventarioRefs = {
    for (final item in reserva.itemsProShop)
      item.productoId: firestore.collection('inventario_general').doc(item.productoId),
  };

  await firestore.runTransaction((transaction) async {
    // Todas las lecturas van antes que cualquier escritura (lo exige
    // Firestore dentro de una transacción).
    for (final slotRef in slotRefs) {
      final slotSnap = await transaction.get(slotRef);
      if (slotSnap.exists) {
        throw HorarioOcupadoException();
      }
    }

    // 🎾 Pro-Shop real: valida que haya stock de cada ítem ANTES de vender
    // nada — si falta aunque sea uno, no se crea ni la reserva ni se
    // descuenta ningún otro stock (todo o nada, mismo criterio que los
    // slots de horario).
    for (final item in reserva.itemsProShop) {
      final invSnap = await transaction.get(inventarioRefs[item.productoId]!);
      final stockActual = (invSnap.data()?['stockActual'] as num?)?.toInt() ?? 0;
      if (!invSnap.exists || stockActual < item.cantidad) {
        throw StockInsuficienteException(item.nombre, stockActual);
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

    for (final item in reserva.itemsProShop) {
      transaction.update(inventarioRefs[item.productoId]!, {
        'stockActual': FieldValue.increment(-item.cantidad),
      });
      transaction.set(firestore.collection('movimientos_stock').doc(), {
        'productoId': item.productoId,
        'productoNombre': item.nombre,
        'tipo': 'Venta Pro-Shop Pádel',
        'cantidad': -item.cantidad,
        'referencia': reserva.id,
        'usuario': null,
        'fecha': FieldValue.serverTimestamp(),
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
  // 🎾 Si la reserva incluía paletas/pelotas del Pro-Shop, el stock vendido
  // se devuelve a inventario_general — antes de conectar el Pro-Shop al
  // stock real esto no hacía falta (era un cargo fijo sin stock detrás).
  for (final item in reserva.itemsProShop) {
    batch.update(
      firestore.collection('inventario_general').doc(item.productoId),
      {'stockActual': FieldValue.increment(item.cantidad)},
    );
    batch.set(firestore.collection('movimientos_stock').doc(), {
      'productoId': item.productoId,
      'productoNombre': item.nombre,
      'tipo': 'Devolución por cancelación (Pádel)',
      'cantidad': item.cantidad,
      'referencia': reserva.id,
      'usuario': null,
      'fecha': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}
