import 'package:cloud_firestore/cloud_firestore.dart';

class InscripcionModel {
  final String id;
  final String socioId;
  final String socioNombre;
  final String profesorId;
  final String profesorNombre;
  final String deporte;
  final String dias; // Ej: "Martes y Jueves" o "Lunes, Miércoles, Viernes"
  final String horario; // Ej: "19:00 - 20:00"
  final DateTime fechaInicio;
  final bool activa;

  InscripcionModel({
    required this.id,
    required this.socioId,
    required this.socioNombre,
    required this.profesorId,
    required this.profesorNombre,
    required this.deporte,
    required this.dias,
    required this.horario,
    required this.fechaInicio,
    required this.activa,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'socioId': socioId,
      'socioNombre': socioNombre,
      'profesorId': profesorId,
      'profesorNombre': profesorNombre,
      'deporte': deporte,
      'dias': dias,
      'horario': horario,
      'fechaInicio': Timestamp.fromDate(fechaInicio),
      'activa': activa,
    };
  }

  factory InscripcionModel.fromFirestore(String id, Map<String, dynamic> data) {
    return InscripcionModel(
      id: id,
      socioId: data['socioId']?.toString() ?? '',
      socioNombre: data['socioNombre']?.toString() ?? '',
      profesorId: data['profesorId']?.toString() ?? '',
      profesorNombre: data['profesorNombre']?.toString() ?? '',
      deporte: data['deporte']?.toString() ?? '',
      dias: data['dias']?.toString() ?? '',
      horario: data['horario']?.toString() ?? '',
      fechaInicio:
          (data['fechaInicio'] as Timestamp?)?.toDate() ?? DateTime.now(),
      activa: data['activa'] ?? true,
    );
  }
}
