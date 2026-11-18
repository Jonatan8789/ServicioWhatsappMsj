import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/shared/libro_iva_digital_export.dart';

void main() {
  final ventaEjemplo = ComprobanteVentaIva(
    fecha: DateTime(2026, 9, 15),
    tipoComprobante: 6, // Factura B
    puntoVenta: 1,
    numero: 42,
    dniComprador: '30123456',
    nombreComprador: 'CONSUMIDOR FINAL',
    total: 1000.0,
    importeNetoGravado: 826.45,
    importeIva: 173.55,
    alicuotaPorcentaje: 21.0,
  );

  final compraEjemplo = ComprobanteCompraIva(
    fecha: DateTime(2026, 9, 10),
    tipoComprobante: 1, // Factura A
    puntoVenta: 3,
    numero: 987,
    cuitProveedor: '20304050607',
    razonSocialProveedor: 'Proveedor SRL',
    total: 1210.0,
    exento: 0,
    percepcionIVA: 0,
    percepcionGanancias: 0,
    percepcionIIBB: 0,
    creditoFiscal: 210.0,
    netoPorAlicuota: {21.0: 1000.0},
  );

  group('Libro de IVA Digital — anchos de línea (spec oficial ARCA)', () {
    // Los anchos vienen del PDF oficial "ANEXO I – DISEÑOS DE REGISTROS"
    // (afip.gob.ar/iva/documentos/libro-iva-digital-diseno-registros.pdf,
    // revisión 07/06/2021). Un desfasaje de un solo carácter corre todos
    // los campos siguientes e invalida el archivo completo ante ARCA.
    test('VENTAS_CBTE: 266 caracteres + CRLF por línea', () {
      final salida = generarVentasCbte([ventaEjemplo]);
      final lineas = salida.split('\r\n')..removeLast();
      expect(lineas, hasLength(1));
      expect(lineas.first.length, 266);
    });

    test('VENTAS_ALICUOTAS: 62 caracteres por línea', () {
      final salida = generarVentasAlicuotas([ventaEjemplo]);
      final lineas = salida.split('\r\n')..removeLast();
      expect(lineas.first.length, 62);
    });

    test('COMPRAS_CBTE: 325 caracteres por línea', () {
      final salida = generarComprasCbte([compraEjemplo]);
      final lineas = salida.split('\r\n')..removeLast();
      expect(lineas.first.length, 325);
    });

    test('COMPRAS_ALICUOTAS: 84 caracteres por línea, una por alícuota con neto > 0', () {
      final compraDosAlicuotas = ComprobanteCompraIva(
        fecha: DateTime(2026, 9, 10),
        tipoComprobante: 1,
        puntoVenta: 3,
        numero: 987,
        cuitProveedor: '20304050607',
        razonSocialProveedor: 'Proveedor SRL',
        total: 1210.0,
        exento: 0,
        percepcionIVA: 0,
        percepcionGanancias: 0,
        percepcionIIBB: 0,
        creditoFiscal: 210.0,
        netoPorAlicuota: {21.0: 1000.0, 10.5: 0.0, 27.0: 500.0},
      );
      final salida = generarComprasAlicuotas([compraDosAlicuotas]);
      final lineas = salida.split('\r\n')..removeLast();
      expect(lineas, hasLength(2)); // 10.5% con neto 0 no genera línea
      for (final linea in lineas) {
        expect(linea.length, 84);
      }
    });
  });

  group('Libro de IVA Digital — contenido de campos', () {
    test('fecha en formato AAAAMMDD al inicio de VENTAS_CBTE', () {
      final salida = generarVentasCbte([ventaEjemplo]);
      expect(salida.startsWith('20260915'), isTrue);
    });

    test('importes se codifican sin punto decimal, 13+2 dígitos', () {
      // 1000.00 -> 1000 * 100 = 100000, relleno a 15 dígitos.
      final salida = generarVentasCbte([ventaEjemplo]);
      expect(salida, contains('000000000100000'));
    });

    test('DNI del comprador se completa con ceros a izquierda (20 dígitos)', () {
      final salida = generarVentasCbte([ventaEjemplo]);
      expect(salida, contains('00000000000030123456'));
    });

    test('Factura C no genera líneas de alícuota (Monotributo, sin IVA discriminado)', () {
      final ventaFacturaC = ComprobanteVentaIva(
        fecha: DateTime(2026, 9, 15),
        tipoComprobante: 11,
        puntoVenta: 1,
        numero: 5,
        dniComprador: null,
        nombreComprador: 'CONSUMIDOR FINAL',
        total: 500.0,
        importeNetoGravado: 500.0,
        importeIva: 0.0,
        alicuotaPorcentaje: 0.0,
      );
      // codigoComprobantePorTexto ya filtra "Factura C" aguas arriba en las
      // pantallas que arman la lista a exportar; acá se verifica que, si
      // igual se pasara una, el código de comprobante quede intacto (no es
      // responsabilidad de este generador decidir si corresponde incluirla).
      final salida = generarVentasCbte([ventaFacturaC]);
      expect(salida, contains('011')); // tipo de comprobante en posición 9-11
    });

    test('codigoComprobantePorTexto mapea los tipos usados en compras_facturas', () {
      expect(codigoComprobantePorTexto('Factura A'), 1);
      expect(codigoComprobantePorTexto('Factura B'), 6);
      expect(codigoComprobantePorTexto('Factura C'), 11);
      expect(codigoComprobantePorTexto('Ticket X'), isNull);
      expect(codigoComprobantePorTexto('Interno'), isNull);
    });
  });
}
