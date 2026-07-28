class TarifaModel {
  final String id;
  final String deporte;
  final String frecuencia;
  final double precio;

  TarifaModel({
    required this.id,
    required this.deporte,
    required this.frecuencia,
    required this.precio,
  });

  // Convertir a Mapa para Firestore
  Map<String, dynamic> toFirestore() {
    return {'deporte': deporte, 'frecuencia': frecuencia, 'precio': precio};
  }

  // Crear desde Firestore
  factory TarifaModel.fromFirestore(String id, Map<String, dynamic> data) {
    return TarifaModel(
      id: id,
      deporte: data['deporte'] ?? '',
      frecuencia: data['frecuencia'] ?? '',
      precio: (data['precio'] ?? 0.0).toDouble(),
    );
  }
}
