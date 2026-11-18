import 'package:cloud_firestore/cloud_firestore.dart';
import 'partido_abierto_model.dart';
import 'reserva_cancha_model.dart';
import 'reserva_cancha_repository.dart';

class PartidoCompletoException implements Exception {
  final String message;
  PartidoCompletoException([
    this.message = 'Ese partido ya completó los 4 jugadores.',
  ]);
  @override
  String toString() => message;
}

class YaAnotadoEnPartidoException implements Exception {
  final String message;
  YaAnotadoEnPartidoException([
    this.message = 'Ya estás anotado en ese partido.',
  ]);
  @override
  String toString() => message;
}

class PartidoNoDisponibleException implements Exception {
  final String message;
  PartidoNoDisponibleException([
    this.message = 'Ese partido ya no está disponible.',
  ]);
  @override
  String toString() => message;
}

/// Crea un Partido Abierto: primero reserva la cancha de forma atómica
/// (reutiliza reserva_cancha_repository.dart, ya probado en la gestión de
/// canchas), y recién si eso se confirma crea el partido con el organizador
/// como primer jugador. El pago de cada jugador NO se debita directo a la
/// cuenta corriente desde el cliente (las reglas de Firestore sólo permiten
/// eso al staff) — en su lugar se genera una 'venta_pendiente', el mismo
/// mecanismo que ya usa el autoservicio de reservas, para que caja la cobre.
Future<PartidoAbiertoModel> crearPartidoAbiertoAtomica({
  required FirebaseFirestore firestore,
  required ReservaCanchaModel reserva,
  required String categoria,
  required String organizadorId,
  required String organizadorNombre,
}) async {
  await reservarCanchaAtomica(firestore: firestore, reserva: reserva);

  final partido = PartidoAbiertoModel(
    id: reserva.id,
    reservaId: reserva.id,
    cancha: reserva.cancha,
    fecha: reserva.fecha,
    horaInicio: reserva.horaInicio,
    duracionHoras: reserva.duracionHoras,
    categoria: categoria,
    precioTotal: reserva.precio,
    jugadoresIds: [organizadorId],
    jugadoresNombres: [organizadorNombre],
    creadoPor: organizadorId,
  );

  await firestore
      .collection('partidos_abiertos')
      .doc(reserva.id)
      .set(partido.toFirestore());

  await _crearVentaPendiente(
    firestore: firestore,
    jugadorId: organizadorId,
    jugadorNombre: organizadorNombre,
    partido: partido,
  );

  return partido;
}

/// Suma un jugador a un Partido Abierto de forma atómica: nunca deja pasar
/// al 5to jugador aunque dos personas confirmen "Unirme" casi al mismo
/// tiempo, y nunca deja anotar dos veces al mismo jugador.
Future<PartidoAbiertoModel> unirseAPartidoAtomica({
  required FirebaseFirestore firestore,
  required String partidoId,
  required String jugadorId,
  required String jugadorNombre,
}) async {
  final partidoRef = firestore.collection('partidos_abiertos').doc(partidoId);

  late PartidoAbiertoModel partidoActualizado;

  await firestore.runTransaction((transaction) async {
    final snap = await transaction.get(partidoRef);
    if (!snap.exists) throw PartidoNoDisponibleException();

    final partido = PartidoAbiertoModel.fromFirestore(snap.id, snap.data()!);

    if (partido.estado == 'Cancelado') throw PartidoNoDisponibleException();
    if (partido.jugadoresIds.contains(jugadorId)) {
      throw YaAnotadoEnPartidoException();
    }
    if (partido.jugadoresIds.length >= PartidoAbiertoModel.cupoJugadores) {
      throw PartidoCompletoException();
    }

    final nuevosIds = [...partido.jugadoresIds, jugadorId];
    final nuevosNombres = [...partido.jugadoresNombres, jugadorNombre];
    final nuevoEstado = nuevosIds.length >= PartidoAbiertoModel.cupoJugadores
        ? 'Completo'
        : 'Abierto';

    transaction.update(partidoRef, {
      'jugadoresIds': nuevosIds,
      'jugadoresNombres': nuevosNombres,
      'estado': nuevoEstado,
    });

    partidoActualizado = PartidoAbiertoModel(
      id: partido.id,
      reservaId: partido.reservaId,
      cancha: partido.cancha,
      fecha: partido.fecha,
      horaInicio: partido.horaInicio,
      duracionHoras: partido.duracionHoras,
      categoria: partido.categoria,
      precioTotal: partido.precioTotal,
      jugadoresIds: nuevosIds,
      jugadoresNombres: nuevosNombres,
      estado: nuevoEstado,
      creadoPor: partido.creadoPor,
    );
  });

  await _crearVentaPendiente(
    firestore: firestore,
    jugadorId: jugadorId,
    jugadorNombre: jugadorNombre,
    partido: partidoActualizado,
  );

  return partidoActualizado;
}

Future<void> _crearVentaPendiente({
  required FirebaseFirestore firestore,
  required String jugadorId,
  required String jugadorNombre,
  required PartidoAbiertoModel partido,
}) {
  return firestore.collection('ventas_pendientes').add({
    'socio_id': jugadorId,
    'nombre_socio': jugadorNombre,
    'origen':
        'Partido Abierto - ${partido.cancha} (${partido.horaInicio}:00 hs)',
    'fecha_creacion': FieldValue.serverTimestamp(),
    'estado': 'Pendiente',
    'items': [
      {
        'id': 'partido_abierto_jugador',
        'nombre':
            'Partido Abierto ${partido.categoria} - ${partido.cancha} (${partido.horaInicio}:00 hs)',
        'precio': partido.montoPorJugador,
        'cantidad': 1,
        'es_producto_fisico': false,
      },
    ],
  });
}
