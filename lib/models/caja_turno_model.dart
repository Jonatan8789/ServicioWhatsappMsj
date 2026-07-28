import 'package:cloud_firestore/cloud_firestore.dart';

class CajaTurnoModel {
  final String? id;
  final String usuario;
  final DateTime fechaApertura;
  final DateTime? fechaCierre;
  final double saldoInicial;
  final double? saldoCierreReal;

  // Canales desglosados unificados con el POS
  final double totalEfectivoARS;
  final double totalEfectivoUSD;
  final double totalMercadoPago;
  final double totalModo;
  final double totalTarjetaDebito;
  final double totalTarjetaCredito;
  final double totalTransferencia;
  final double totalCtaCte;

  final String estado; // 'Abierta' o 'Cerrada'

  CajaTurnoModel({
    this.id,
    required this.usuario,
    required this.fechaApertura,
    this.fechaCierre,
    required this.saldoInicial,
    this.saldoCierreReal,
    this.totalEfectivoARS = 0.0,
    this.totalEfectivoUSD = 0.0,
    this.totalMercadoPago = 0.0,
    this.totalModo = 0.0,
    this.totalTarjetaDebito = 0.0,
    this.totalTarjetaCredito = 0.0,
    this.totalTransferencia = 0.0,
    this.totalCtaCte = 0.0,
    required this.estado,
  });

  // Calculador teórico automático para el Arqueo Final de Tesorería
  double get totalTeoricoAcumulado {
    return saldoInicial +
        totalEfectivoARS +
        totalEfectivoUSD +
        totalMercadoPago +
        totalModo +
        totalTarjetaDebito +
        totalTarjetaCredito +
        totalTransferencia;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'usuario': usuario,
      'fechaApertura': fechaApertura,
      'fechaCierre': fechaCierre,
      'saldoInicial': saldoInicial,
      'saldoCierreReal': saldoCierreReal,
      'totalEfectivoARS': totalEfectivoARS,
      'totalEfectivoUSD': totalEfectivoUSD,
      'totalMercadoPago': totalMercadoPago,
      'totalModo': totalModo,
      'totalTarjetaDebito': totalTarjetaDebito,
      'totalTarjetaCredito': totalTarjetaCredito,
      'totalTransferencia': totalTransferencia,
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
      totalEfectivoARS:
          (data['totalEfectivoARS'] ?? data['totalEfectivo'] as num?)
              ?.toDouble() ??
          0.0,
      totalEfectivoUSD: (data['totalEfectivoUSD'] as num?)?.toDouble() ?? 0.0,
      totalMercadoPago: (data['totalMercadoPago'] as num?)?.toDouble() ?? 0.0,
      totalModo: (data['totalModo'] as num?)?.toDouble() ?? 0.0,
      totalTarjetaDebito:
          (data['totalTarjetaDebito'] as num?)?.toDouble() ?? 0.0,
      totalTarjetaCredito:
          (data['totalTarjetaCredito'] as num?)?.toDouble() ?? 0.0,
      totalTransferencia:
          (data['totalTransferencia'] as num?)?.toDouble() ?? 0.0,
      totalCtaCte: (data['totalCtaCte'] as num?)?.toDouble() ?? 0.0,
      estado: data['estado'] ?? 'Cerrada',
    );
  }
}
