import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/socios/socio_model.dart';

void main() {
  group('vencimientoVigente', () {
    test('null nunca está vigente', () {
      expect(vencimientoVigente(null, DateTime(2026, 11, 16)), isFalse);
    });

    test(
      'sigue vigente durante TODO el día de vencimiento, aunque ya haya '
      'pasado la medianoche (antes `isAfter` lo cortaba a las 00:00)',
      () {
        final vencimiento = DateTime(2026, 11, 16); // vence el 16/11
        final hoyALaTarde = DateTime(2026, 11, 16, 23, 59);
        expect(vencimientoVigente(vencimiento, hoyALaTarde), isTrue);
      },
    );

    test('deja de estar vigente recién al día siguiente del vencimiento', () {
      final vencimiento = DateTime(2026, 11, 16);
      final diaSiguiente = DateTime(2026, 11, 17, 0, 1);
      expect(vencimientoVigente(vencimiento, diaSiguiente), isFalse);
    });

    test('está vigente con margen amplio antes del vencimiento', () {
      final vencimiento = DateTime(2026, 11, 16);
      final unMesAntes = DateTime(2026, 10, 16);
      expect(vencimientoVigente(vencimiento, unMesAntes), isTrue);
    });
  });
}
