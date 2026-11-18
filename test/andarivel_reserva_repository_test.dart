import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/natatorio/andarivel_reserva_model.dart';
import 'package:natatorio_app/features/natatorio/andarivel_reserva_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  AndarivelReservaModel reserva({
    required String socioId,
    int horaInicio = 9,
    String andarivel = 'Andarivel 1',
    String categoria = 'Libre',
  }) {
    return AndarivelReservaModel(
      id: 'sin-usar',
      andarivel: andarivel,
      categoria: categoria,
      nombreCliente: 'Socio $socioId',
      socioId: socioId,
      fecha: DateTime(2026, 11, 16),
      horaInicio: horaInicio,
    );
  }

  group('reservarAndariveloAtomica', () {
    test('permite reservar mientras haya cupo', () async {
      await reservarAndariveloAtomica(
        firestore: firestore,
        reserva: reserva(socioId: 's1'),
        cupoMaximo: 2,
      );
      await reservarAndariveloAtomica(
        firestore: firestore,
        reserva: reserva(socioId: 's2'),
        cupoMaximo: 2,
      );

      final snap = await firestore.collection('reservas_andariveles').get();
      expect(snap.docs.length, 2);
    });

    test('rechaza la reserva número cupoMaximo+1 en el mismo turno', () async {
      await reservarAndariveloAtomica(
        firestore: firestore,
        reserva: reserva(socioId: 's1'),
        cupoMaximo: 2,
      );
      await reservarAndariveloAtomica(
        firestore: firestore,
        reserva: reserva(socioId: 's2'),
        cupoMaximo: 2,
      );

      expect(
        () => reservarAndariveloAtomica(
          firestore: firestore,
          reserva: reserva(socioId: 's3'),
          cupoMaximo: 2,
        ),
        throwsA(isA<CupoLlenoException>()),
      );

      final snap = await firestore.collection('reservas_andariveles').get();
      expect(snap.docs.length, 2);
    });

    test(
      'el mismo socio no puede anotarse dos veces al mismo turno (y no gasta cupo doble)',
      () async {
        await reservarAndariveloAtomica(
          firestore: firestore,
          reserva: reserva(socioId: 's1'),
          cupoMaximo: 2,
        );

        expect(
          () => reservarAndariveloAtomica(
            firestore: firestore,
            reserva: reserva(socioId: 's1'),
            cupoMaximo: 2,
          ),
          throwsA(isA<YaAnotadoException>()),
        );

        final cupoDoc = await firestore
            .collection('cupos_andariveles')
            .doc('2026-11-16_Andarivel1_9hs')
            .get();
        expect(cupoDoc.data()!['ocupados'], 1);
      },
    );

    test(
      'rechaza una categoría distinta para un turno que ya quedó fijado por otra reserva',
      () async {
        await reservarAndariveloAtomica(
          firestore: firestore,
          reserva: reserva(socioId: 's1', categoria: 'Escuela'),
          cupoMaximo: 12,
        );

        expect(
          () => reservarAndariveloAtomica(
            firestore: firestore,
            reserva: reserva(socioId: 's2', categoria: 'Libre'),
            cupoMaximo: 6,
          ),
          throwsA(isA<CategoriaDelTurnoException>()),
        );
      },
    );

    test('horarios distintos no comparten cupo', () async {
      await reservarAndariveloAtomica(
        firestore: firestore,
        reserva: reserva(socioId: 's1', horaInicio: 9),
        cupoMaximo: 1,
      );
      await reservarAndariveloAtomica(
        firestore: firestore,
        reserva: reserva(socioId: 's2', horaInicio: 10),
        cupoMaximo: 1,
      );

      final snap = await firestore.collection('reservas_andariveles').get();
      expect(snap.docs.length, 2);
    });
  });

  group('cancelarAndariveloAtomica', () {
    test('libera un lugar del cupo para que otro socio pueda entrar', () async {
      final r1 = reserva(socioId: 's1');
      await reservarAndariveloAtomica(
        firestore: firestore,
        reserva: r1,
        cupoMaximo: 1,
      );

      final reservaGuardada = await firestore
          .collection('reservas_andariveles')
          .doc('2026-11-16_Andarivel1_9hs_s1')
          .get();
      final reservaConId = AndarivelReservaModel.fromFirestore(
        reservaGuardada.id,
        reservaGuardada.data()!,
      );

      await cancelarAndariveloAtomica(
        firestore: firestore,
        reserva: reservaConId,
      );

      final cupoDoc = await firestore
          .collection('cupos_andariveles')
          .doc('2026-11-16_Andarivel1_9hs')
          .get();
      expect(cupoDoc.data()!['ocupados'], 0);

      // Si no se hubiera liberado, esto fallaría con CupoLlenoException.
      await reservarAndariveloAtomica(
        firestore: firestore,
        reserva: reserva(socioId: 's2'),
        cupoMaximo: 1,
      );
    });
  });
}
