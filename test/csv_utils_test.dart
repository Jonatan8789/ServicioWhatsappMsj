import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/shared/csv_utils.dart';

void main() {
  group('celdaCsv', () {
    test('valores simples no se entrecomillan', () {
      expect(celdaCsv('Juan Perez'), 'Juan Perez');
      expect(celdaCsv(123), '123');
      expect(celdaCsv(null), '');
    });

    test('comas fuerzan comillas', () {
      expect(celdaCsv('Perez, Juan'), '"Perez, Juan"');
    });

    test('comillas internas se duplican', () {
      expect(celdaCsv('Socio "VIP"'), '"Socio ""VIP"""');
    });

    test('saltos de línea fuerzan comillas', () {
      expect(celdaCsv('linea1\nlinea2'), '"linea1\nlinea2"');
    });
  });

  group('generarCsv', () {
    test('arma encabezado + filas con CRLF y BOM inicial', () {
      final csv = generarCsv(
        ['Nombre', 'DNI'],
        [
          ['Juan Perez', '12345678'],
          ['Ana, García', '87654321'],
        ],
      );
      expect(csv.startsWith('﻿'), isTrue);
      expect(csv.contains('Nombre,DNI\r\n'), isTrue);
      expect(csv.contains('Juan Perez,12345678\r\n'), isTrue);
      expect(csv.contains('"Ana, García",87654321\r\n'), isTrue);
    });

    test('filas vacías produce sólo el encabezado', () {
      final csv = generarCsv(['A', 'B'], []);
      expect(csv, '﻿A,B\r\n');
    });
  });
}
