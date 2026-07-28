class BloqueHorarioModel {
  final String id;
  final String inicio;
  final String fin;
  final String nombre;

  BloqueHorarioModel({
    required this.id,
    required this.inicio,
    required this.fin,
    required this.nombre,
  });

  // ADAPTADO: Mapea correctamente usando 'horaInicio' y 'horaFin' de tu Firestore
  factory BloqueHorarioModel.fromMap(Map<String, dynamic> map) {
    return BloqueHorarioModel(
      id: map['id'] ?? '',
      inicio: map['horaInicio'] ?? '', // Mapea 'horaInicio' de Firebase
      fin: map['horaFin'] ?? '', // Mapea 'horaFin' de Firebase
      nombre:
          map['nombre'] ??
          '', // Si no tiene nombre comercial, usará un texto vacío
    );
  }

  // Arma la etiqueta visual prolija para el dropdown
  String get etiquetaVisual {
    if (nombre.isEmpty) {
      return '$inicio a $fin hs';
    }
    return '$inicio a $fin hs ($nombre)';
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'horaInicio': inicio, 'horaFin': fin, 'nombre': nombre};
  }
}
