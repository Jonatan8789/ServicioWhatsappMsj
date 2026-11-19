import 'package:cloud_firestore/cloud_firestore.dart';
import 'clase_padel_model.dart';
import 'paddle_ids.dart';
import 'reserva_cancha_model.dart';
import 'reserva_cancha_repository.dart';

/// Se lanza cuando una clase ya no acepta inscripciones (no existe más o
/// fue cancelada).
class ClaseNoDisponibleException implements Exception {
  final String message;
  ClaseNoDisponibleException([this.message = 'Esa clase ya no está disponible.']);
  @override
  String toString() => message;
}

/// Se lanza cuando el socio ya está anotado (inscripto o en lista de
/// espera) en esa misma clase.
class YaInscriptoEnClasePadelException implements Exception {
  final String message;
  YaInscriptoEnClasePadelException([
    this.message = 'Ya estás anotado en esta clase (o en su lista de espera).',
  ]);
  @override
  String toString() => message;
}

String _idPagoClasePadel(String claseId, String socioId) => '${claseId}_$socioId';

/// Crea los documentos de pago (`pagos_clases_padel`) y de cobro en caja
/// (`ventas_pendientes`) para un alumno recién entrado a la clase — nunca
/// para alguien que queda en lista de espera (no se le cobra hasta que
/// entre de verdad).
///
/// 🚨 `ventaSocioId` es el valor que se guarda en `ventas_pendientes.socio_id`
/// — campo que la regla de Firestore de esa colección exige que sea
/// exactamente `request.auth.uid` cuando quien escribe es el propio socio
/// (ver `reserva_cancha_screen.dart`, que ya usa el mismo truco). Si quien
/// ejecuta la transacción es staff, el valor no importa para la regla (la
/// cubre `esStaffOperativo()`), pero se mantiene el id de `socios/{id}` por
/// consistencia con el resto del sistema.
void _generarPagoYVentaPendiente(
  FirebaseFirestore firestore,
  Transaction transaction, {
  required ClasePadelModel clase,
  required String socioId,
  required String socioNombre,
  required String ventaSocioId,
}) {
  final pagoRef = firestore
      .collection('pagos_clases_padel')
      .doc(_idPagoClasePadel(clase.id, socioId));
  final ventaRef = firestore.collection('ventas_pendientes').doc();

  transaction.set(
    pagoRef,
    PagoClasePadelModel(
      id: pagoRef.id,
      claseId: clase.id,
      claseNombre: clase.nombre,
      fecha: clase.fecha,
      profesorId: clase.profesorId,
      socioId: socioId,
      socioNombre: socioNombre,
      monto: clase.precioPorAlumno,
      ventaPendienteId: ventaRef.id,
    ).toFirestore(),
  );

  transaction.set(ventaRef, {
    'socio_id': ventaSocioId,
    'nombre_socio': socioNombre,
    'origen': 'Clase de Pádel: ${clase.nombre} (${fechaIdStrCancha(clase.fecha)})',
    'fecha_creacion': FieldValue.serverTimestamp(),
    'estado': 'Pendiente',
    'items': [
      {
        'id': 'clase_padel_alumno',
        'nombre': 'Clase de Pádel: ${clase.nombre}',
        'precio': clase.precioPorAlumno,
        'cantidad': 1,
        'es_producto_fisico': false,
      },
    ],
  });
}

/// Crea una clase de pádel puntual: bloquea la cancha (reusa
/// `reservarCanchaAtomica`, mismo mecanismo anti-solapamiento que cualquier
/// otra reserva) y crea el doc de la clase apuntando a esa reserva.
Future<ClasePadelModel> crearClasePadelAtomica({
  required FirebaseFirestore firestore,
  required String nombre,
  required String profesorId,
  required String profesorNombre,
  required String cancha,
  required DateTime fecha,
  required int horaInicio,
  required int duracionHoras,
  required int cupoMaximo,
  required double precioPorAlumno,
  required String creadoPor,
  String? turnoRecurrenteClaseId,
}) async {
  final reservaId = idReservaCancha(
    fecha: fecha,
    cancha: cancha,
    horaInicio: horaInicio,
    duracionHoras: duracionHoras,
  );

  // 🎾 La cancha se bloquea con el mismo mecanismo que cualquier reserva
  // (reservas_canchas + reservas_canchas_slots) — así una clase nunca puede
  // solaparse con una reserva normal, un turno fijo o un partido abierto.
  // nombreCliente queda como "Clase de Pádel: ..." para que la grilla de
  // canchas_page.dart la muestre identificada sin tocar esa pantalla.
  await reservarCanchaAtomica(
    firestore: firestore,
    reserva: ReservaCanchaModel(
      id: reservaId,
      cancha: cancha,
      nombreCliente: 'Clase de Pádel: $nombre ($profesorNombre)',
      fecha: fecha,
      horaInicio: horaInicio,
      duracionHoras: duracionHoras,
      precio: 0,
      metodoPago: 'Clase de Pádel',
    ),
  );

  final claseRef = firestore.collection('clases_padel').doc();
  final clase = ClasePadelModel(
    id: claseRef.id,
    nombre: nombre,
    profesorId: profesorId,
    profesorNombre: profesorNombre,
    cancha: cancha,
    fecha: fecha,
    horaInicio: horaInicio,
    duracionHoras: duracionHoras,
    cupoMaximo: cupoMaximo,
    precioPorAlumno: precioPorAlumno,
    reservaId: reservaId,
    turnoRecurrenteClaseId: turnoRecurrenteClaseId,
    creadoPor: creadoPor,
  );
  await claseRef.set(clase.toFirestore());
  return clase;
}

/// Inscribe a un socio en una clase de pádel: si hay cupo, entra directo y
/// se le genera el pago (`pagos_clases_padel` + `ventas_pendientes`); si no
/// hay cupo, se anota al final de la lista de espera SIN cobrarle nada
/// todavía. Todo en una transacción (mismo criterio que
/// `clase_gimnasio_repository.dart`) para que dos inscripciones casi
/// simultáneas nunca pisen el mismo último lugar.
///
/// `ventaSocioId` es quién paga la "venta pendiente" generada — ver el
/// comentario de `_generarPagoYVentaPendiente`. Siempre es la MISMA persona
/// que se inscribe (nunca un tercero), así que esta función es segura de
/// llamar tanto desde el staff como desde el propio socio.
///
/// Devuelve `true` si entró directo, `false` si quedó en lista de espera.
Future<bool> inscribirseAClasePadelAtomica({
  required FirebaseFirestore firestore,
  required String claseId,
  required String socioId,
  required String socioNombre,
  required String ventaSocioId,
}) async {
  final claseRef = firestore.collection('clases_padel').doc(claseId);
  late bool entroDirecto;

  await firestore.runTransaction((transaction) async {
    final snap = await transaction.get(claseRef);
    if (!snap.exists) {
      throw ClaseNoDisponibleException('Esa clase ya no existe.');
    }
    final clase = ClasePadelModel.fromFirestore(snap.id, snap.data()!);
    if (clase.estadoClase != 'Programada') {
      throw ClaseNoDisponibleException('Esa clase fue cancelada.');
    }
    if (clase.inscriptosIds.contains(socioId) ||
        clase.listaEsperaIds.contains(socioId)) {
      throw YaInscriptoEnClasePadelException();
    }

    if (clase.inscriptosIds.length < clase.cupoMaximo) {
      entroDirecto = true;
      transaction.update(claseRef, {
        'inscriptosIds': [...clase.inscriptosIds, socioId],
        'inscriptosNombres': [...clase.inscriptosNombres, socioNombre],
      });
      _generarPagoYVentaPendiente(
        firestore,
        transaction,
        clase: clase,
        socioId: socioId,
        socioNombre: socioNombre,
        ventaSocioId: ventaSocioId,
      );
    } else {
      entroDirecto = false;
      transaction.update(claseRef, {
        'listaEsperaIds': [...clase.listaEsperaIds, socioId],
        'listaEsperaNombres': [...clase.listaEsperaNombres, socioNombre],
      });
    }
  });

  return entroDirecto;
}

/// Cancela la inscripción (o el lugar en lista de espera) de un socio. Si
/// salía de los inscriptos efectivos y había alguien esperando, promueve al
/// primero de la lista (FIFO) y recién ahí le genera su pago — mismo
/// criterio que gimnasio, pero acá además hay que resolver qué pasa con el
/// dinero: al que se da de baja, si todavía no había pagado, se le borra el
/// pago pendiente (nada que cobrar); si ya estaba pagado, el registro queda
/// como histórico (no hay reintegro automático).
///
/// 🚨 SOLO PARA STAFF (o Admin SDK): si promueve a alguien de la lista de
/// espera, crea la `ventas_pendientes` de ESA OTRA PERSONA dentro de la
/// misma transacción. Un socio cancelando su propia inscripción no puede
/// ejecutar esto directo desde el cliente — la regla de Firestore de
/// `ventas_pendientes` exige que `socio_id` sea igual a `request.auth.uid`
/// de quien escribe, y acá quien escribe es el que cancela, no el
/// promovido. El autoservicio del socio pasa por la Cloud Function
/// `cancelarInscripcionClasePadelSocio`, que hace esto mismo con el Admin
/// SDK (sin pasar por las reglas).
Future<void> cancelarInscripcionClasePadelAtomica({
  required FirebaseFirestore firestore,
  required String claseId,
  required String socioId,
}) async {
  final claseRef = firestore.collection('clases_padel').doc(claseId);
  final pagoDelQueSeVaRef = firestore
      .collection('pagos_clases_padel')
      .doc(_idPagoClasePadel(claseId, socioId));

  await firestore.runTransaction((transaction) async {
    final claseSnap = await transaction.get(claseRef);
    if (!claseSnap.exists) return;
    final clase = ClasePadelModel.fromFirestore(claseSnap.id, claseSnap.data()!);
    // Todas las lecturas antes que cualquier escritura (lo exige Firestore).
    final pagoSnap = await transaction.get(pagoDelQueSeVaRef);

    final int idxInscripto = clase.inscriptosIds.indexOf(socioId);
    if (idxInscripto != -1) {
      final nuevosInscriptosIds = [...clase.inscriptosIds]
        ..removeAt(idxInscripto);
      final nuevosInscriptosNombres = [...clase.inscriptosNombres]
        ..removeAt(idxInscripto);
      List<String> nuevaEsperaIds = clase.listaEsperaIds;
      List<String> nuevaEsperaNombres = clase.listaEsperaNombres;
      String? promovidoId;
      String? promovidoNombre;

      if (nuevaEsperaIds.isNotEmpty) {
        promovidoId = nuevaEsperaIds.first;
        promovidoNombre = nuevaEsperaNombres.first;
        nuevosInscriptosIds.add(promovidoId);
        nuevosInscriptosNombres.add(promovidoNombre);
        nuevaEsperaIds = nuevaEsperaIds.sublist(1);
        nuevaEsperaNombres = nuevaEsperaNombres.sublist(1);
      }

      transaction.update(claseRef, {
        'inscriptosIds': nuevosInscriptosIds,
        'inscriptosNombres': nuevosInscriptosNombres,
        'listaEsperaIds': nuevaEsperaIds,
        'listaEsperaNombres': nuevaEsperaNombres,
      });

      if (pagoSnap.exists) {
        final pago = PagoClasePadelModel.fromFirestore(
          pagoSnap.id,
          pagoSnap.data()!,
        );
        if (!pago.estaPago) {
          transaction.delete(pagoDelQueSeVaRef);
        }
      }

      if (promovidoId != null) {
        // ventaSocioId = el id de socios/{id} (no un auth.uid): esta rama
        // sólo corre con permisos de staff/Admin SDK (ver el aviso arriba
        // de esta función), así que la regla de auto-servicio no aplica.
        _generarPagoYVentaPendiente(
          firestore,
          transaction,
          clase: clase,
          socioId: promovidoId,
          socioNombre: promovidoNombre!,
          ventaSocioId: promovidoId,
        );
      }
      return;
    }

    final int idxEspera = clase.listaEsperaIds.indexOf(socioId);
    if (idxEspera != -1) {
      final nuevaEsperaIds = [...clase.listaEsperaIds]..removeAt(idxEspera);
      final nuevaEsperaNombres = [...clase.listaEsperaNombres]
        ..removeAt(idxEspera);
      transaction.update(claseRef, {
        'listaEsperaIds': nuevaEsperaIds,
        'listaEsperaNombres': nuevaEsperaNombres,
      });
      // Alguien en lista de espera nunca tuvo pago generado, nada que limpiar.
    }
  });
}
