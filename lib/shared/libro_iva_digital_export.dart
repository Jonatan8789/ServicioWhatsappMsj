import 'package:intl/intl.dart';

/// Genera los 4 archivos de texto de ancho fijo que exige ARCA (ex-AFIP)
/// para el Libro de IVA Digital (R.G. 4597) — el mismo formato que usaba
/// el régimen CITI (RG 3685) y que hoy se usa para importar comprobantes
/// al Portal IVA en bloque en vez de cargarlos uno por uno a mano.
///
/// Especificación verificada contra el PDF oficial vigente (revisión
/// 07/06/2021): afip.gob.ar/iva/documentos/libro-iva-digital-diseno-registros.pdf
///
/// 🚨 IMPORTANTE: el Libro de IVA sólo existe para quien discrimina IVA
/// (Responsable Inscripto — Factura A/B). Un Monotributista que factura
/// exclusivamente Factura C (como el club, mientras no complete el pase a
/// Responsable Inscripto) no tiene nada que declarar acá — por diseño,
/// las Facturas C se excluyen de este export y los archivos salen vacíos
/// hasta que el club empiece a facturar A/B de verdad.

// ═══════════════════════════════════════════════════════════════════════
// HELPERS DE FORMATO DE CAMPO
// ═══════════════════════════════════════════════════════════════════════

String _alfa(String valor, int ancho) {
  final limpio = valor.length > ancho ? valor.substring(0, ancho) : valor;
  return limpio.padRight(ancho);
}

String _num(String valor, int ancho) {
  final soloDigitos = valor.replaceAll(RegExp(r'\D'), '');
  final limpio = soloDigitos.length > ancho
      ? soloDigitos.substring(soloDigitos.length - ancho)
      : soloDigitos;
  return limpio.padLeft(ancho, '0');
}

/// Campos de importe: "N enteros M decimales sin punto decimal" — se
/// multiplica por 10^decimales, se redondea a entero y se rellena con
/// ceros a la izquierda hasta (enteros+decimales) posiciones.
String _importe(double valor, int enteros, int decimales) {
  final factor = decimales == 6 ? 1000000 : 100;
  final centavos = (valor.abs() * factor).round();
  return centavos.toString().padLeft(enteros + decimales, '0');
}

String _fechaAAAAMMDD(DateTime d) => DateFormat('yyyyMMdd').format(d);

/// Tabla de Comprobantes de AFIP — coinciden con los CbteTipo de WSFE que
/// ya usa functions/index.js (emitirFacturaArca): 1=Factura A, 6=Factura
/// B, 11=Factura C.
int? codigoComprobantePorTexto(String texto) {
  final t = texto.toLowerCase();
  if (t.contains('factura a')) return 1;
  if (t.contains('factura b')) return 6;
  if (t.contains('factura c')) return 11;
  if (t.contains('nota de crédito a') || t.contains('nota de credito a')) return 3;
  if (t.contains('nota de crédito b') || t.contains('nota de credito b')) return 8;
  if (t.contains('nota de débito a') || t.contains('nota de debito a')) return 2;
  if (t.contains('nota de débito b') || t.contains('nota de debito b')) return 7;
  return null; // Ticket X, Interno, Recibo, etc. — no son comprobantes fiscales A/B
}

/// Tabla Alícuotas de IVA de AFIP: 3=0%, 4=10.5%, 5=21%, 6=27%, 8=5%, 9=2.5%.
String _codigoAlicuota(double porcentaje) {
  if (porcentaje == 0) return '3';
  if (porcentaje == 10.5) return '4';
  if (porcentaje == 27) return '6';
  if (porcentaje == 5) return '8';
  if (porcentaje == 2.5) return '9';
  return '5'; // 21%, el caso normal del club
}

const String _finLinea = '\r\n';

// ═══════════════════════════════════════════════════════════════════════
// VENTAS
// ═══════════════════════════════════════════════════════════════════════

class ComprobanteVentaIva {
  final DateTime fecha;
  final int tipoComprobante;
  final int puntoVenta;
  final int numero;
  final String? dniComprador;
  final String nombreComprador;
  final double total;
  final double importeNetoGravado;
  final double importeIva;
  final double alicuotaPorcentaje;

  ComprobanteVentaIva({
    required this.fecha,
    required this.tipoComprobante,
    required this.puntoVenta,
    required this.numero,
    required this.dniComprador,
    required this.nombreComprador,
    required this.total,
    required this.importeNetoGravado,
    required this.importeIva,
    required this.alicuotaPorcentaje,
  });
}

/// LIBRO_IVA_DIGITAL_VENTAS_CBTE — 266 caracteres, 22 campos por comprobante.
String generarVentasCbte(List<ComprobanteVentaIva> ventas) {
  final buffer = StringBuffer();
  for (final v in ventas) {
    buffer.write(_fechaAAAAMMDD(v.fecha)); // 1) Fecha de comprobante (8)
    buffer.write(_num(v.tipoComprobante.toString(), 3)); // 2) Tipo comprobante (3)
    buffer.write(_num(v.puntoVenta.toString(), 5)); // 3) Punto de venta (5)
    buffer.write(_num(v.numero.toString(), 20)); // 4) N° comprobante (20)
    buffer.write(_num(v.numero.toString(), 20)); // 5) N° comprobante hasta (20)
    buffer.write(v.dniComprador != null && v.dniComprador!.isNotEmpty ? '96' : '99'); // 6) Cód. doc. comprador (2)
    buffer.write(_num(v.dniComprador ?? '0', 20)); // 7) N° identificación comprador (20)
    buffer.write(_alfa(v.nombreComprador, 30)); // 8) Apellido y nombre comprador (30)
    buffer.write(_importe(v.total, 13, 2)); // 9) Importe total operación (15)
    buffer.write(_importe(0, 13, 2)); // 10) Conceptos no gravados (15)
    buffer.write(_importe(0, 13, 2)); // 11) Percepción a no categorizados (15)
    buffer.write(_importe(0, 13, 2)); // 12) Operaciones exentas (15)
    buffer.write(_importe(0, 13, 2)); // 13) Percepciones/pagos a cta. Nacionales (15)
    buffer.write(_importe(0, 13, 2)); // 14) Percepciones Ingresos Brutos (15)
    buffer.write(_importe(0, 13, 2)); // 15) Percepciones Municipales (15)
    buffer.write(_importe(0, 13, 2)); // 16) Impuestos internos (15)
    buffer.write(_alfa('PES', 3)); // 17) Código de moneda (3)
    buffer.write(_importe(1.0, 4, 6)); // 18) Tipo de cambio (10) — 1:1 en pesos
    buffer.write('1'); // 19) Cantidad de alícuotas de IVA (1) — siempre 1 (tasa única por venta)
    buffer.write(' '); // 20) Código de operación (1) — en blanco (no exportación/otros regímenes)
    buffer.write(_importe(0, 13, 2)); // 21) Otros tributos (15)
    buffer.write(_fechaAAAAMMDD(v.fecha)); // 22) Fecha de vencimiento o pago (8)
    buffer.write(_finLinea);
  }
  return buffer.toString();
}

/// LIBRO_IVA_DIGITAL_VENTAS_ALICUOTAS — 62 caracteres, 6 campos.
String generarVentasAlicuotas(List<ComprobanteVentaIva> ventas) {
  final buffer = StringBuffer();
  for (final v in ventas) {
    buffer.write(_num(v.tipoComprobante.toString(), 3)); // 1) Tipo comprobante (3)
    buffer.write(_num(v.puntoVenta.toString(), 5)); // 2) Punto de venta (5)
    buffer.write(_num(v.numero.toString(), 20)); // 3) N° comprobante (20)
    buffer.write(_importe(v.importeNetoGravado, 13, 2)); // 4) Importe neto gravado (15)
    buffer.write(_codigoAlicuota(v.alicuotaPorcentaje).padLeft(4, '0')); // 5) Alícuota IVA (4)
    buffer.write(_importe(v.importeIva, 13, 2)); // 6) Impuesto liquidado (15)
    buffer.write(_finLinea);
  }
  return buffer.toString();
}

// ═══════════════════════════════════════════════════════════════════════
// COMPRAS
// ═══════════════════════════════════════════════════════════════════════

class ComprobanteCompraIva {
  final DateTime fecha;
  final int tipoComprobante;
  final int puntoVenta;
  final int numero;
  final String cuitProveedor;
  final String razonSocialProveedor;
  final double total;
  final double exento;
  final double percepcionIVA;
  final double percepcionGanancias;
  final double percepcionIIBB;
  final double creditoFiscal;
  // Neto gravado discriminado por alícuota (21, 10.5, 27, etc.)
  final Map<double, double> netoPorAlicuota;

  ComprobanteCompraIva({
    required this.fecha,
    required this.tipoComprobante,
    required this.puntoVenta,
    required this.numero,
    required this.cuitProveedor,
    required this.razonSocialProveedor,
    required this.total,
    required this.exento,
    required this.percepcionIVA,
    required this.percepcionGanancias,
    required this.percepcionIIBB,
    required this.creditoFiscal,
    required this.netoPorAlicuota,
  });
}

/// LIBRO_IVA_DIGITAL_COMPRAS_CBTE — 325 caracteres, 25 campos.
String generarComprasCbte(List<ComprobanteCompraIva> compras) {
  final buffer = StringBuffer();
  for (final c in compras) {
    final int cantAlicuotas = c.netoPorAlicuota.values.where((v) => v > 0).length;
    buffer.write(_fechaAAAAMMDD(c.fecha)); // 1) Fecha comprobante (8)
    buffer.write(_num(c.tipoComprobante.toString(), 3)); // 2) Tipo comprobante (3)
    buffer.write(_num(c.puntoVenta.toString(), 5)); // 3) Punto de venta (5)
    buffer.write(_num(c.numero.toString(), 20)); // 4) N° comprobante (20)
    buffer.write(_alfa('', 16)); // 5) Despacho de importación (16) — no aplica
    buffer.write('80'); // 6) Código documento vendedor (2) — CUIT
    buffer.write(_num(c.cuitProveedor, 20)); // 7) N° identificación vendedor (20)
    buffer.write(_alfa(c.razonSocialProveedor, 30)); // 8) Apellido/nombre vendedor (30)
    buffer.write(_importe(c.total, 13, 2)); // 9) Importe total operación (15)
    buffer.write(_importe(0, 13, 2)); // 10) Conceptos no gravados (15)
    buffer.write(_importe(c.exento, 13, 2)); // 11) Operaciones exentas (15)
    buffer.write(_importe(c.percepcionIVA, 13, 2)); // 12) Percepciones/pagos a cta. IVA (15)
    buffer.write(_importe(c.percepcionGanancias, 13, 2)); // 13) Percepciones otros imp. nacionales (15)
    buffer.write(_importe(c.percepcionIIBB, 13, 2)); // 14) Percepciones Ingresos Brutos (15)
    buffer.write(_importe(0, 13, 2)); // 15) Percepciones Municipales (15)
    buffer.write(_importe(0, 13, 2)); // 16) Impuestos internos (15)
    buffer.write(_alfa('PES', 3)); // 17) Código de moneda (3)
    buffer.write(_importe(1.0, 4, 6)); // 18) Tipo de cambio (10)
    buffer.write(cantAlicuotas.toString()); // 19) Cantidad de alícuotas de IVA (1)
    buffer.write(' '); // 20) Código de operación (1)
    buffer.write(_importe(c.creditoFiscal, 13, 2)); // 21) Crédito fiscal computable (15)
    buffer.write(_importe(0, 13, 2)); // 22) Otros tributos (15)
    buffer.write(_num('0', 11)); // 23) CUIT emisor/corredor (11) — no aplica
    buffer.write(_alfa('', 30)); // 24) Denominación emisor/corredor (30)
    buffer.write(_importe(0, 13, 2)); // 25) IVA comisión (15)
    buffer.write(_finLinea);
  }
  return buffer.toString();
}

/// LIBRO_IVA_DIGITAL_COMPRAS_ALICUOTAS — 84 caracteres, 8 campos, una
/// línea por cada alícuota con neto gravado > 0 dentro del comprobante.
String generarComprasAlicuotas(List<ComprobanteCompraIva> compras) {
  final buffer = StringBuffer();
  for (final c in compras) {
    for (final entry in c.netoPorAlicuota.entries) {
      if (entry.value <= 0) continue;
      final double impuestoLiquidado = entry.value * (entry.key / 100);
      buffer.write(_num(c.tipoComprobante.toString(), 3)); // 1) Tipo comprobante (3)
      buffer.write(_num(c.puntoVenta.toString(), 5)); // 2) Punto de venta (5)
      buffer.write(_num(c.numero.toString(), 20)); // 3) N° comprobante (20)
      buffer.write('80'); // 4) Código documento vendedor (2)
      buffer.write(_num(c.cuitProveedor, 20)); // 5) N° identificación vendedor (20)
      buffer.write(_importe(entry.value, 13, 2)); // 6) Importe neto gravado (15)
      buffer.write(_codigoAlicuota(entry.key).padLeft(4, '0')); // 7) Alícuota IVA (4)
      buffer.write(_importe(impuestoLiquidado, 13, 2)); // 8) Impuesto liquidado (15)
      buffer.write(_finLinea);
    }
  }
  return buffer.toString();
}
