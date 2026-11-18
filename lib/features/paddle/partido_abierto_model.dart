import 'package:cloud_firestore/cloud_firestore.dart';

class PartidoAbiertoModel {
  final String id;
  final String reservaId;
  final String cancha;
  final DateTime fecha;
  final int horaInicio;
  final int duracionHoras;
  final String categoria;
  final double precioTotal;
  final double montoPorJugador;
  final List<String> jugadoresIds;
  final List<String> jugadoresNombres;
  final String estado; // 'Abierto', 'Completo', 'Cancelado'
  final String creadoPor;

  static const int cupoJugadores = 4;

  PartidoAbiertoModel({
    required this.id,
    required this.reservaId,
    required this.cancha,
    required this.fecha,
    required this.horaInicio,
    required this.duracionHoras,
    required this.categoria,
    required this.precioTotal,
    required this.jugadoresIds,
    required this.jugadoresNombres,
    this.estado = 'Abierto',
    required this.creadoPor,
  }) : montoPorJugador = precioTotal / cupoJugadores;

  Map<String, dynamic> toFirestore() {
    return {
      'reservaId': reservaId,
      'cancha': cancha,
      'fecha': Timestamp.fromDate(fecha),
      'horaInicio': horaInicio,
      'duracionHoras': duracionHoras,
      'categoria': categoria,
      'precioTotal': precioTotal,
      'jugadoresIds': jugadoresIds,
      'jugadoresNombres': jugadoresNombres,
      'estado': estado,
      'creadoPor': creadoPor,
      'creadoEn': FieldValue.serverTimestamp(),
    };
  }

  factory PartidoAbiertoModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return PartidoAbiertoModel(
      id: id,
      reservaId: data['reservaId']?.toString() ?? '',
      cancha: data['cancha']?.toString() ?? '',
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      horaInicio: (data['horaInicio'] as num?)?.toInt() ?? 0,
      duracionHoras: (data['duracionHoras'] as num?)?.toInt() ?? 1,
      categoria: data['categoria']?.toString() ?? 'Sin categoría',
      precioTotal: (data['precioTotal'] as num?)?.toDouble() ?? 0.0,
      jugadoresIds: List<String>.from(data['jugadoresIds'] ?? []),
      jugadoresNombres: List<String>.from(data['jugadoresNombres'] ?? []),
      estado: data['estado']?.toString() ?? 'Abierto',
      creadoPor: data['creadoPor']?.toString() ?? '',
    );
  }
}
