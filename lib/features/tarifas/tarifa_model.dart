import 'package:cloud_firestore/cloud_firestore.dart';

class TarifaModel {
  final String id;
  final String deporte;
  final String frecuencia;
  final double precioRegular;
  final double precioEfectivo;
  final DateTime fechaDesde;
  final DateTime? fechaHasta;

  // 🏷️ CAMPOS PARA PROMOCIONES Y PAQUETES
  final String tipo; // 'REGULAR' o 'PROMOCION'
  final int duracionMeses; // 1, 3 o 6 meses
  final double? valorFinalTotal; // Para combos de 3 o 6 meses
  final String? leyendaPromocion; // Ej: "Hasta 3 cuotas sin interés"

  TarifaModel({
    required this.id,
    required this.deporte,
    required this.frecuencia,
    required this.precioRegular,
    required this.precioEfectivo,
    required this.fechaDesde,
    this.fechaHasta,
    this.tipo = 'REGULAR',
    this.duracionMeses = 1,
    this.valorFinalTotal,
    this.leyendaPromocion,
  });

  double get precio => precioRegular;

  bool esVigenteEn(DateTime fecha) {
    final f = DateTime(fecha.year, fecha.month, fecha.day);
    final desde = DateTime(fechaDesde.year, fechaDesde.month, fechaDesde.day);
    if (f.isBefore(desde)) return false;

    if (fechaHasta != null) {
      final hasta = DateTime(
        fechaHasta!.year,
        fechaHasta!.month,
        fechaHasta!.day,
      );
      if (f.isAfter(hasta)) return false;
    }
    return true;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'deporte': deporte,
      'frecuencia': frecuencia,
      'precioRegular': precioRegular,
      'precioEfectivo': precioEfectivo,
      'precio': precioRegular,
      'fechaDesde': Timestamp.fromDate(fechaDesde),
      'fechaHasta': fechaHasta != null ? Timestamp.fromDate(fechaHasta!) : null,
      'tipo': tipo,
      'duracionMeses': duracionMeses,
      'valorFinalTotal': valorFinalTotal,
      'leyendaPromocion': leyendaPromocion,
      'fechaCreacion': FieldValue.serverTimestamp(),
    };
  }

  factory TarifaModel.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? parseFecha(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final double pReg = (data['precioRegular'] ?? data['precio'] ?? 0.0)
        .toDouble();
    final double pEfect = (data['precioEfectivo'] ?? pReg).toDouble();

    return TarifaModel(
      id: id,
      deporte: data['deporte'] ?? 'Natatorio',
      frecuencia: data['frecuencia'] ?? 'Pase Libre',
      precioRegular: pReg,
      precioEfectivo: pEfect,
      fechaDesde: parseFecha(data['fechaDesde']) ?? DateTime.now(),
      fechaHasta: parseFecha(data['fechaHasta']),
      tipo: data['tipo'] ?? 'REGULAR',
      duracionMeses: (data['duracionMeses'] as num?)?.toInt() ?? 1,
      valorFinalTotal: (data['valorFinalTotal'] as num?)?.toDouble(),
      leyendaPromocion: data['leyendaPromocion']?.toString(),
    );
  }
}
