import 'package:cloud_firestore/cloud_firestore.dart';

class TransaccionModel {
  final String id;
  final String idSocio;
  final DateTime fecha;
  final String tipo; // 'DEBITO' o 'CREDITO'
  final String concepto;
  final double monto;

  TransaccionModel({
    required this.id,
    required this.idSocio,
    required this.fecha,
    required this.tipo,
    required this.concepto,
    required this.monto,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'idSocio': idSocio,
      'fecha': Timestamp.fromDate(fecha),
      'tipo': tipo,
      'concepto': concepto,
      'monto': monto,
    };
  }

  factory TransaccionModel.fromFirestore(String id, Map<String, dynamic> data) {
    return TransaccionModel(
      id: id,
      idSocio: data['idSocio'] ?? '',
      fecha: (data['fecha'] as Timestamp).toDate(),
      tipo: data['tipo'] ?? 'DEBITO',
      concepto: data['concepto'] ?? '',
      monto: (data['monto'] ?? 0.0).toDouble(),
    );
  }
}
