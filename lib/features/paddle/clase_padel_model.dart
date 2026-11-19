import 'package:cloud_firestore/cloud_firestore.dart';

/// Clase de pádel con cupo, lista de espera y cobro por alumno.
///
/// Mismo patrón que `ClaseGimnasioModel` (cupo + lista de espera FIFO), pero
/// a diferencia de gimnasio: ocupa una cancha real (`reservaId` referencia
/// el doc en `reservas_canchas` que la bloquea) y SÍ se cobra por alumno
/// (ver `pagos_clases_padel`, un doc por alumno por ocurrencia).
class ClasePadelModel {
  final String id;
  final String nombre;
  final String profesorId;
  final String profesorNombre;
  final String cancha;
  final DateTime fecha;
  final int horaInicio;
  final int duracionHoras;
  final int cupoMaximo;
  final double precioPorAlumno;
  final String reservaId;
  final List<String> inscriptosIds;
  final List<String> inscriptosNombres;
  final List<String> listaEsperaIds;
  final List<String> listaEsperaNombres;
  final String estadoClase; // 'Programada' | 'Cancelada'
  final String? turnoRecurrenteClaseId;
  final String creadoPor;

  ClasePadelModel({
    required this.id,
    required this.nombre,
    required this.profesorId,
    required this.profesorNombre,
    required this.cancha,
    required this.fecha,
    required this.horaInicio,
    required this.duracionHoras,
    required this.cupoMaximo,
    required this.precioPorAlumno,
    required this.reservaId,
    this.inscriptosIds = const [],
    this.inscriptosNombres = const [],
    this.listaEsperaIds = const [],
    this.listaEsperaNombres = const [],
    this.estadoClase = 'Programada',
    this.turnoRecurrenteClaseId,
    required this.creadoPor,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'profesorId': profesorId,
      'profesorNombre': profesorNombre,
      'cancha': cancha,
      'fecha': Timestamp.fromDate(fecha),
      'horaInicio': horaInicio,
      'duracionHoras': duracionHoras,
      'cupoMaximo': cupoMaximo,
      'precioPorAlumno': precioPorAlumno,
      'reservaId': reservaId,
      'inscriptosIds': inscriptosIds,
      'inscriptosNombres': inscriptosNombres,
      'listaEsperaIds': listaEsperaIds,
      'listaEsperaNombres': listaEsperaNombres,
      'estadoClase': estadoClase,
      'turnoRecurrenteClaseId': turnoRecurrenteClaseId,
      'creadoPor': creadoPor,
    };
  }

  factory ClasePadelModel.fromFirestore(String id, Map<String, dynamic> data) {
    return ClasePadelModel(
      id: id,
      nombre: data['nombre']?.toString() ?? '',
      profesorId: data['profesorId']?.toString() ?? '',
      profesorNombre: data['profesorNombre']?.toString() ?? '',
      cancha: data['cancha']?.toString() ?? '',
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      horaInicio: (data['horaInicio'] as num?)?.toInt() ?? 0,
      duracionHoras: (data['duracionHoras'] as num?)?.toInt() ?? 1,
      cupoMaximo: (data['cupoMaximo'] as num?)?.toInt() ?? 0,
      precioPorAlumno: (data['precioPorAlumno'] as num?)?.toDouble() ?? 0.0,
      reservaId: data['reservaId']?.toString() ?? '',
      inscriptosIds: List<String>.from(data['inscriptosIds'] ?? []),
      inscriptosNombres: List<String>.from(data['inscriptosNombres'] ?? []),
      listaEsperaIds: List<String>.from(data['listaEsperaIds'] ?? []),
      listaEsperaNombres: List<String>.from(data['listaEsperaNombres'] ?? []),
      estadoClase: data['estadoClase']?.toString() ?? 'Programada',
      turnoRecurrenteClaseId: data['turnoRecurrenteClaseId']?.toString(),
      creadoPor: data['creadoPor']?.toString() ?? '',
    );
  }
}

/// Pago de UN alumno por UNA ocurrencia de clase — separado de los arrays
/// de `ClasePadelModel` porque esos no son queryables por socio/mes (es la
/// auditoría de pagos de clases que pide el punto 8 del pedido).
class PagoClasePadelModel {
  final String id;
  final String claseId;
  final String claseNombre;
  final DateTime fecha;
  final String profesorId;
  final String socioId;
  final String socioNombre;
  final double monto;
  // Circuito manual (caja): lo marca el staff desde "Registrar pago manual".
  final bool cobrado;
  final String? medioPago;
  final DateTime? fechaPago;
  // Circuito online (Mercado Pago, Fase 4): campo separado de 'cobrado' a
  // propósito, para que el webhook y el cobro manual nunca se pisen entre sí.
  final String estadoPagoMP; // 'Pendiente' | 'Aprobado'
  final String? ventaPendienteId;

  PagoClasePadelModel({
    required this.id,
    required this.claseId,
    required this.claseNombre,
    required this.fecha,
    required this.profesorId,
    required this.socioId,
    required this.socioNombre,
    required this.monto,
    this.cobrado = false,
    this.medioPago,
    this.fechaPago,
    this.estadoPagoMP = 'Pendiente',
    this.ventaPendienteId,
  });

  bool get estaPago => cobrado || estadoPagoMP == 'Aprobado';

  Map<String, dynamic> toFirestore() {
    return {
      'claseId': claseId,
      'claseNombre': claseNombre,
      'fecha': Timestamp.fromDate(fecha),
      'profesorId': profesorId,
      'socioId': socioId,
      'socioNombre': socioNombre,
      'monto': monto,
      'cobrado': cobrado,
      'medioPago': medioPago,
      'fechaPago': fechaPago != null ? Timestamp.fromDate(fechaPago!) : null,
      'estadoPagoMP': estadoPagoMP,
      'ventaPendienteId': ventaPendienteId,
    };
  }

  factory PagoClasePadelModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return PagoClasePadelModel(
      id: id,
      claseId: data['claseId']?.toString() ?? '',
      claseNombre: data['claseNombre']?.toString() ?? '',
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      profesorId: data['profesorId']?.toString() ?? '',
      socioId: data['socioId']?.toString() ?? '',
      socioNombre: data['socioNombre']?.toString() ?? '',
      monto: (data['monto'] as num?)?.toDouble() ?? 0.0,
      cobrado: data['cobrado'] as bool? ?? false,
      medioPago: data['medioPago']?.toString(),
      fechaPago: (data['fechaPago'] as Timestamp?)?.toDate(),
      estadoPagoMP: data['estadoPagoMP']?.toString() ?? 'Pendiente',
      ventaPendienteId: data['ventaPendienteId']?.toString(),
    );
  }
}
