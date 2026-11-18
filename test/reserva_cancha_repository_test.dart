import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/paddle/reserva_cancha_model.dart';
import 'package:natatorio_app/features/paddle/reserva_cancha_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ReservaCanchaModel reserva({
    required String id,
    required int horaInicio,
    int duracionHoras = 1,
    String cancha = 'Cancha 1 Cristal',
  }) {
    return ReservaCanchaModel(
      id: id,
      cancha: cancha,
      nombreCliente: 'Socio de prueba',
      fecha: DateTime(2026, 11, 16),
      horaInicio: horaInicio,
      duracionHoras: duracionHoras,
      precio: 4500,
      metodoPago: 'Cuenta Corriente',
    );
  }

  group('reservarCanchaAtomica', () {
    test('crea la reserva y sus slots cuando el horario está libre', () async {
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'r1', horaInicio: 10),
      );

      final doc = await firestore.collection('reservas_canchas').doc('r1').get();
      expect(doc.exists, isTrue);

      final slot = await firestore
          .collection('reservas_canchas_slots')
          .doc('2026-11-16_Cancha1Cristal_10hs')
          .get();
      expect(slot.exists, isTrue);
    });

    test(
      'rechaza una segunda reserva con el mismo id exacto (misma cancha/hora/duración) '
      'en vez de pisar silenciosamente a la primera',
      () async {
        await reservarCanchaAtomica(
          firestore: firestore,
          reserva: reserva(id: 'mismo_id', horaInicio: 10),
        );

        expect(
          () => reservarCanchaAtomica(
            firestore: firestore,
            reserva: reserva(id: 'mismo_id', horaInicio: 10),
          ),
          throwsA(isA<HorarioOcupadoException>()),
        );

        // La reserva original sigue intacta: no fue sobreescrita.
        final doc = await firestore
            .collection('reservas_canchas')
            .doc('mismo_id')
            .get();
        expect(doc.data()!['nombreCliente'], 'Socio de prueba');
      },
    );

    test(
      'rechaza una reserva que se solapa parcialmente con otra de distinta duración '
      '(antes esto generaba dos documentos "válidos" para la misma hora)',
      () async {
        // Reserva de 2 horas: ocupa 9 y 10.
        await reservarCanchaAtomica(
          firestore: firestore,
          reserva: reserva(id: 'r_larga', horaInicio: 9, duracionHoras: 2),
        );

        // Otra reserva de 1 hora a las 10 (distinto id, mismo bloque horario real).
        expect(
          () => reservarCanchaAtomica(
            firestore: firestore,
            reserva: reserva(id: 'r_corta', horaInicio: 10),
          ),
          throwsA(isA<HorarioOcupadoException>()),
        );
      },
    );

    test('permite reservar horas distintas en la misma cancha sin conflicto', () async {
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'r_9', horaInicio: 9),
      );
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'r_10', horaInicio: 10),
      );

      final snap = await firestore.collection('reservas_canchas').get();
      expect(snap.docs.length, 2);
    });

    test('permite reservar la misma hora en canchas distintas', () async {
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'cancha1', horaInicio: 10, cancha: 'Cancha 1 Cristal'),
      );
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'cancha2', horaInicio: 10, cancha: 'Cancha 2 Cristal'),
      );

      final snap = await firestore.collection('reservas_canchas').get();
      expect(snap.docs.length, 2);
    });
  });

  group('cancelarReservaCanchaAtomica', () {
    test('libera el horario para que pueda volver a reservarse', () async {
      final r = reserva(id: 'cancelable', horaInicio: 14);
      await reservarCanchaAtomica(firestore: firestore, reserva: r);

      await cancelarReservaCanchaAtomica(firestore: firestore, reserva: r);

      final doc = await firestore
          .collection('reservas_canchas')
          .doc('cancelable')
          .get();
      expect(doc.exists, isFalse);

      // Si el slot no se hubiera liberado, esto fallaría con HorarioOcupadoException.
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'nueva_despues_de_cancelar', horaInicio: 14),
      );
    });
  });
}
