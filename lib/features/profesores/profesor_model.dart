class ProfesorModel {
  final String id;
  final String nombre;
  final String dni;
  final String telefono;
  final List<String> especialidades; // Múltiples especialidades
  final bool activo;

  // 💡 GETTER DE RETROCOMPATIBILIDAD:
  // Retorna todas las especialidades unidas por comas o vacíos si no tiene.
  String get especialidad => especialidades.join(', ');

  ProfesorModel({
    required this.id,
    required this.nombre,
    required this.dni,
    required this.telefono,
    required this.especialidades,
    required this.activo,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'dni': dni,
      'telefono': telefono,
      'especialidades': especialidades,
      'activo': activo,
    };
  }

  factory ProfesorModel.fromFirestore(String id, Map<String, dynamic> data) {
    return ProfesorModel(
      id: id,
      nombre: data['nombre'] ?? '',
      dni: data['dni'] ?? '',
      telefono: data['telefono'] ?? '',
      especialidades: List<String>.from(data['especialidades'] ?? []),
      activo: data['activo'] ?? true,
    );
  }
}
