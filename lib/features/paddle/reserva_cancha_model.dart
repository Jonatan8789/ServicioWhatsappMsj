import 'package:cloud_firestore/cloud_firestore.dart';

class ReservaCanchaModel {
  final String id;
  final String cancha;
  final String nombreCliente;
  final String? socioId;
  final DateTime fecha;
  final int horaInicio;
  final int duracionHoras;
  final double precio;
  final String metodoPago;

  ReservaCanchaModel({
    required this.id,
    required this.cancha,
    required this.nombreCliente,
    this.socioId,
    required this.fecha,
    required this.horaInicio,
    required this.duracionHoras,
    required this.precio,
    required this.metodoPago,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'cancha': cancha,
      'nombreCliente': nombreCliente,
      'socioId': socioId,
      'fecha': Timestamp.fromDate(fecha),
      'horaInicio': horaInicio,
      'duracionHoras': duracionHoras,
      'precio': precio,
      'metodoPago': metodoPago,
    };
  }

  factory ReservaCanchaModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return ReservaCanchaModel(
      id: id,
      cancha: data['cancha']?.toString() ?? '',
      nombreCliente: data['nombreCliente']?.toString() ?? '',
      socioId: data['socioId']?.toString(),
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      horaInicio: (data['horaInicio'] as num?)?.toInt() ?? 0,
      duracionHoras: (data['duracionHoras'] as num?)?.toInt() ?? 0,
      precio: (data['precio'] as num?)?.toDouble() ?? 0.0,
      metodoPago: data['metodoPago']?.toString() ?? 'Efectivo',
    );
  }
}
