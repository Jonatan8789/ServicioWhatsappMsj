import 'package:cloud_firestore/cloud_firestore.dart';

class ClaseGimnasioModel {
  final String id;
  final String nombre;
  final String profesorNombre;
  final DateTime fecha;
  final int horaInicio;
  final int cupoMaximo;
  final List<String> inscriptosIds;
  final List<String> inscriptosNombres;
  final List<String> listaEsperaIds;
  final List<String> listaEsperaNombres;

  ClaseGimnasioModel({
    required this.id,
    required this.nombre,
    required this.profesorNombre,
    required this.fecha,
    required this.horaInicio,
    required this.cupoMaximo,
    this.inscriptosIds = const [],
    this.inscriptosNombres = const [],
    this.listaEsperaIds = const [],
    this.listaEsperaNombres = const [],
  });

  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'profesorNombre': profesorNombre,
      'fecha': Timestamp.fromDate(fecha),
      'horaInicio': horaInicio,
      'cupoMaximo': cupoMaximo,
      'inscriptosIds': inscriptosIds,
      'inscriptosNombres': inscriptosNombres,
      'listaEsperaIds': listaEsperaIds,
      'listaEsperaNombres': listaEsperaNombres,
    };
  }

  factory ClaseGimnasioModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return ClaseGimnasioModel(
      id: id,
      nombre: data['nombre']?.toString() ?? '',
      profesorNombre: data['profesorNombre']?.toString() ?? '',
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      horaInicio: (data['horaInicio'] as num?)?.toInt() ?? 0,
      cupoMaximo: (data['cupoMaximo'] as num?)?.toInt() ?? 0,
      inscriptosIds: List<String>.from(data['inscriptosIds'] ?? []),
      inscriptosNombres: List<String>.from(data['inscriptosNombres'] ?? []),
      listaEsperaIds: List<String>.from(data['listaEsperaIds'] ?? []),
      listaEsperaNombres: List<String>.from(data['listaEsperaNombres'] ?? []),
    );
  }
}
