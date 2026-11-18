import 'package:cloud_firestore/cloud_firestore.dart';

class EjercicioRutina {
  final String nombre;
  final int series;
  final int repeticiones;
  final int descansoSegundos;

  EjercicioRutina({
    required this.nombre,
    required this.series,
    required this.repeticiones,
    required this.descansoSegundos,
  });

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    'series': series,
    'repeticiones': repeticiones,
    'descansoSegundos': descansoSegundos,
  };

  factory EjercicioRutina.fromMap(Map<String, dynamic> m) {
    return EjercicioRutina(
      nombre: m['nombre']?.toString() ?? '',
      series: (m['series'] as num?)?.toInt() ?? 0,
      repeticiones: (m['repeticiones'] as num?)?.toInt() ?? 0,
      descansoSegundos: (m['descansoSegundos'] as num?)?.toInt() ?? 0,
    );
  }
}

class RutinaModel {
  final String socioId;
  final List<EjercicioRutina> ejercicios;
  final String asignadoPorNombre;
  final DateTime fechaAsignacion;
  final String notas;

  RutinaModel({
    required this.socioId,
    required this.ejercicios,
    required this.asignadoPorNombre,
    required this.fechaAsignacion,
    this.notas = '',
  });

  Map<String, dynamic> toFirestore() {
    return {
      'ejercicios': ejercicios.map((e) => e.toMap()).toList(),
      'asignadoPorNombre': asignadoPorNombre,
      'fechaAsignacion': Timestamp.fromDate(fechaAsignacion),
      'notas': notas,
    };
  }

  factory RutinaModel.fromFirestore(String socioId, Map<String, dynamic> data) {
    return RutinaModel(
      socioId: socioId,
      ejercicios: (data['ejercicios'] as List? ?? [])
          .map((e) => EjercicioRutina.fromMap(e as Map<String, dynamic>))
          .toList(),
      asignadoPorNombre: data['asignadoPorNombre']?.toString() ?? '',
      fechaAsignacion:
          (data['fechaAsignacion'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notas: data['notas']?.toString() ?? '',
    );
  }
}
