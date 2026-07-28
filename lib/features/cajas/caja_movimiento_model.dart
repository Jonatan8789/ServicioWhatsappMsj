import 'package:cloud_firestore/cloud_firestore.dart';

class CajaTurnoModel {
  final String? id;
  final String usuario;
  final DateTime fechaApertura;
  final DateTime? fechaCierre;
  final double saldoInicial;
  final double? saldoCierreReal; // Lo que el cajero dice que contó al irse
  final double totalEfectivo;
  final double totalMercadoPago;
  final double totalCtaCte;
  final String estado; // 'Abierta' o 'Cerrada'

  CajaTurnoModel({
    this.id,
    required this.usuario,
    required this.fechaApertura,
    this.fechaCierre,
    required this.saldoInicial,
    this.saldoCierreReal,
    this.totalEfectivo = 0.0,
    this.totalMercadoPago = 0.0,
    this.totalCtaCte = 0.0,
    required this.estado,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'usuario': usuario,
      'fechaApertura': fechaApertura,
      'fechaCierre': fechaCierre,
      'saldoInicial': saldoInicial,
      'saldoCierreReal': saldoCierreReal,
      'totalEfectivo': totalEfectivo,
      'totalMercadoPago': totalMercadoPago,
      'totalCtaCte': totalCtaCte,
      'estado': estado,
    };
  }

  factory CajaTurnoModel.fromFirestore(String id, Map<String, dynamic> data) {
    return CajaTurnoModel(
      id: id,
      usuario: data['usuario'] ?? '',
      fechaApertura: (data['fechaApertura'] as Timestamp).toDate(),
      fechaCierre: data['fechaCierre'] != null
          ? (data['fechaCierre'] as Timestamp).toDate()
          : null,
      saldoInicial: (data['saldoInicial'] as num?)?.toDouble() ?? 0.0,
      saldoCierreReal: (data['saldoCierreReal'] as num?)?.toDouble(),
      totalEfectivo: (data['totalEfectivo'] as num?)?.toDouble() ?? 0.0,
      totalMercadoPago: (data['totalMercadoPago'] as num?)?.toDouble() ?? 0.0,
      totalCtaCte: (data['totalCtaCte'] as num?)?.toDouble() ?? 0.0,
      estado: data['estado'] ?? 'Cerrada',
    );
  }
}
