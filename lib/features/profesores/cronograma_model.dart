class CronogramaModel {
  final String id;
  final String idProfesor;
  final String nombreProfesor;
  final String deporte;
  final List<String> dias; // Ej: ['Lunes', 'Miércoles']
  final String
  idBloqueHorario; // El ID o texto del bloque (ej: "19:00 a 20:00")

  CronogramaModel({
    required this.id,
    required this.idProfesor,
    required this.nombreProfesor,
    required this.deporte,
    required this.dias,
    required this.idBloqueHorario,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'idProfesor': idProfesor,
      'nombreProfesor': nombreProfesor,
      'deporte': deporte,
      'dias': dias,
      'idBloqueHorario': idBloqueHorario,
    };
  }

  factory CronogramaModel.fromFirestore(String id, Map<String, dynamic> data) {
    return CronogramaModel(
      id: id,
      idProfesor: data['idProfesor'] ?? '',
      nombreProfesor: data['nombreProfesor'] ?? '',
      deporte: data['deporte'] ?? '',
      dias: List<String>.from(data['dias'] ?? []),
      idBloqueHorario: data['idBloqueHorario'] ?? '',
    );
  }
}
