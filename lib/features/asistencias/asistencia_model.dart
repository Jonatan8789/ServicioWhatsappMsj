import 'package:cloud_firestore/cloud_firestore.dart';

class AsistenciaModel {
  final String id;
  final String profesorId;
  final String nombreProfesor;
  final String specialty; // o 'especialidad' si usás español
  final DateTime fecha;
  final String tipo; // 'Entrada' o 'Salida'
  final String hora; // 'HH:mm'

  AsistenciaModel({
    required this.id,
    required this.profesorId,
    required this.nombreProfesor,
    required this.specialty,
    required this.fecha,
    required this.tipo,
    required this.hora,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'profesorId': profesorId,
      'nombreProfesor': nombreProfesor,
      'especialidad': specialty,
      'fecha': Timestamp.fromDate(fecha),
      'tipo': tipo,
      'hora': hora,
    };
  }

  factory AsistenciaModel.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime fechaParseada;
    if (data['fecha'] is Timestamp) {
      fechaParseada = (data['fecha'] as Timestamp).toDate();
    } else if (data['fecha'] is String) {
      fechaParseada = DateTime.tryParse(data['fecha']) ?? DateTime.now();
    } else {
      fechaParseada = DateTime.now();
    }

    return AsistenciaModel(
      id: id,
      profesorId: data['profesorId']?.toString() ?? '',
      nombreProfesor: data['nombreProfesor']?.toString() ?? '',
      specialty: data['especialidad']?.toString() ?? '',
      fecha: fechaParseada,
      tipo: data['tipo']?.toString() ?? '',
      hora: data['hora']?.toString() ?? '--:--',
    );
  }
}
