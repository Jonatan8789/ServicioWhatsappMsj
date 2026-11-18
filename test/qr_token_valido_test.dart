import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/socios/socio_model.dart';

void main() {
  group('qrTokenValido', () {
    test('válido si el token coincide y no venció', () {
      final ahora = DateTime(2026, 11, 16, 10, 0);
      final data = {
        'qrTokenActual': 'abc123',
        'qrTokenExpira': Timestamp.fromDate(ahora.add(const Duration(seconds: 10))),
      };
      expect(qrTokenValido(data, 'abc123', ahora), isTrue);
    });

    test('inválido si el token no coincide (foto vieja de otro QR)', () {
      final ahora = DateTime(2026, 11, 16, 10, 0);
      final data = {
        'qrTokenActual': 'abc123',
        'qrTokenExpira': Timestamp.fromDate(ahora.add(const Duration(seconds: 10))),
      };
      expect(qrTokenValido(data, 'token-viejo-de-una-captura', ahora), isFalse);
    });

    test('inválido si ya venció, aunque el token coincida', () {
      final ahora = DateTime(2026, 11, 16, 10, 0);
      final data = {
        'qrTokenActual': 'abc123',
        'qrTokenExpira': Timestamp.fromDate(ahora.subtract(const Duration(seconds: 1))),
      };
      expect(qrTokenValido(data, 'abc123', ahora), isFalse);
    });

    test('inválido si el socio nunca generó un token', () {
      expect(qrTokenValido(<String, dynamic>{}, 'cualquiera'), isFalse);
    });
  });
}
