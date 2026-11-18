import 'package:cloud_firestore/cloud_firestore.dart';

class AndarivelReservaModel {
  final String id;
  final String andarivel;
  final String categoria; // 'Libre', 'Escuela', 'Rehabilitación'
  final String nombreCliente;
  final String? socioId;
  final DateTime fecha;
  final int horaInicio;
  final String estado;

  AndarivelReservaModel({
    required this.id,
    required this.andarivel,
    required this.categoria,
    required this.nombreCliente,
    this.socioId,
    required this.fecha,
    required this.horaInicio,
    this.estado = 'Confirmada',
  });

  Map<String, dynamic> toFirestore() {
    return {
      'andarivel': andarivel,
      'categoria': categoria,
      'nombreCliente': nombreCliente,
      'socioId': socioId,
      'fecha': Timestamp.fromDate(fecha),
      'horaInicio': horaInicio,
      'estado': estado,
      'creadoEn': FieldValue.serverTimestamp(),
    };
  }

  factory AndarivelReservaModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return AndarivelReservaModel(
      id: id,
      andarivel: data['andarivel']?.toString() ?? '',
      categoria: data['categoria']?.toString() ?? 'Libre',
      nombreCliente: data['nombreCliente']?.toString() ?? '',
      socioId: data['socioId']?.toString(),
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      horaInicio: (data['horaInicio'] as num?)?.toInt() ?? 0,
      estado: data['estado']?.toString() ?? 'Confirmada',
    );
  }
}
