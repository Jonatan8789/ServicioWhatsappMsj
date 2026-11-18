import 'package:cloud_firestore/cloud_firestore.dart';
import 'andarivel_reserva_model.dart';

/// A diferencia de una cancha de pádel, un andarivel no es exclusivo: varias
/// personas comparten el mismo andarivel/horario hasta un cupo máximo (que
/// depende de la categoría asignada a ese bloque: Libre, Escuela o
/// Rehabilitación). Por eso la concurrencia acá no es "primero en llegar se
/// queda con todo el bloque" como en pádel, sino "mientras haya cupo, entra".
class CupoLlenoException implements Exception {
  final String message;
  CupoLlenoException([
    this.message = 'Ese andarivel/horario ya alcanzó el cupo máximo.',
  ]);
  @override
  String toString() => message;
}

class YaAnotadoException implements Exception {
  final String message;
  YaAnotadoException([
    this.message = 'Ya tenés una reserva en ese andarivel y horario.',
  ]);
  @override
  String toString() => message;
}

/// La categoría (y por lo tanto el cupo) de un andarivel/horario la fija la
/// PRIMERA reserva de ese turno. Sin este chequeo, una carrera entre dos
/// reservas con categorías distintas para el mismo turno vacío podría dejar
/// el cupo/categoría efectivos en lo que haya escrito la segunda, aunque la
/// primera ya haya quedado confirmada con la categoría original.
class CategoriaDelTurnoException implements Exception {
  final String message;
  CategoriaDelTurnoException([
    this.message =
        'Ese horario ya quedó asignado a otra categoría. Elegí otro turno.',
  ]);
  @override
  String toString() => message;
}

String _idCupo(String andarivel, DateTime fecha, int horaInicio) {
  final fechaIdStr = "${fecha.year}-${fecha.month}-${fecha.day}";
  final andarivelLimpio = andarivel.replaceAll(' ', '');
  return '${fechaIdStr}_${andarivelLimpio}_${horaInicio}hs';
}

/// Reserva un lugar en un andarivel garantizando, a nivel de Firestore, que
/// nunca se supere el cupo máximo de esa categoría/horario — aunque varias
/// personas confirmen casi al mismo tiempo. Usa un documento contador
/// ('cupos_andariveles') que se lee y escribe dentro de la misma transacción
/// que la reserva individual, así Firestore rechaza cualquier intento que
/// haga superar el cupo.
Future<void> reservarAndariveloAtomica({
  required FirebaseFirestore firestore,
  required AndarivelReservaModel reserva,
  required int cupoMaximo,
}) async {
  final cupoRef = firestore
      .collection('cupos_andariveles')
      .doc(_idCupo(reserva.andarivel, reserva.fecha, reserva.horaInicio));

  // Id determinístico por socio: si ya está anotado en este mismo
  // andarivel/horario, reintentar no debe contarlo dos veces; si es un
  // invitado sin socioId (carga manual de recepción), usa un id propio.
  final reservaRef = reserva.socioId != null
      ? firestore
            .collection('reservas_andariveles')
            .doc(
              '${_idCupo(reserva.andarivel, reserva.fecha, reserva.horaInicio)}_${reserva.socioId}',
            )
      : firestore.collection('reservas_andariveles').doc();

  await firestore.runTransaction((transaction) async {
    final cupoSnap = await transaction.get(cupoRef);
    final reservaSnap = await transaction.get(reservaRef);

    if (reservaSnap.exists) {
      throw YaAnotadoException();
    }

    final int ocupadosActuales = cupoSnap.exists
        ? ((cupoSnap.data()!['ocupados'] as num?)?.toInt() ?? 0)
        : 0;
    if (cupoSnap.exists &&
        cupoSnap.data()!['categoria'] != reserva.categoria) {
      throw CategoriaDelTurnoException();
    }
    if (ocupadosActuales >= cupoMaximo) {
      throw CupoLlenoException();
    }

    final fechaDia = DateTime(
      reserva.fecha.year,
      reserva.fecha.month,
      reserva.fecha.day,
    );
    transaction.set(cupoRef, {
      'andarivel': reserva.andarivel,
      'categoria': reserva.categoria,
      'fecha': Timestamp.fromDate(fechaDia),
      'horaInicio': reserva.horaInicio,
      'cupoMaximo': cupoMaximo,
      'ocupados': ocupadosActuales + 1,
    });
    transaction.set(reservaRef, reserva.toFirestore());
  });
}

/// Cancela una reserva de andarivel y libera un lugar del cupo, de forma
/// atómica (evita que el contador de 'ocupados' quede desincronizado si dos
/// cancelaciones del mismo turno corren a la vez).
Future<void> cancelarAndariveloAtomica({
  required FirebaseFirestore firestore,
  required AndarivelReservaModel reserva,
}) async {
  final cupoRef = firestore
      .collection('cupos_andariveles')
      .doc(_idCupo(reserva.andarivel, reserva.fecha, reserva.horaInicio));
  final reservaRef = firestore
      .collection('reservas_andariveles')
      .doc(reserva.id);

  await firestore.runTransaction((transaction) async {
    final cupoSnap = await transaction.get(cupoRef);
    final reservaSnap = await transaction.get(reservaRef);
    if (!reservaSnap.exists) return;

    transaction.delete(reservaRef);
    if (cupoSnap.exists) {
      final int ocupadosActuales =
          (cupoSnap.data()!['ocupados'] as num?)?.toInt() ?? 0;
      transaction.update(cupoRef, {
        'ocupados': ocupadosActuales > 0 ? ocupadosActuales - 1 : 0,
      });
    }
  });
}
