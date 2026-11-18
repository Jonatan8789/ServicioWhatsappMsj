import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/paddle/partido_abierto_repository.dart';
import 'package:natatorio_app/features/paddle/reserva_cancha_model.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ReservaCanchaModel reservaBase({String id = 'reserva1'}) {
    return ReservaCanchaModel(
      id: id,
      cancha: 'Cancha 1 Cristal',
      nombreCliente: 'Organizador',
      socioId: 'organizador1',
      fecha: DateTime(2026, 11, 16),
      horaInicio: 10,
      duracionHoras: 1,
      precio: 4800,
      metodoPago: 'Cuenta Corriente',
    );
  }

  group('crearPartidoAbiertoAtomica', () {
    test(
      'reserva la cancha, crea el partido con el organizador y genera su venta pendiente',
      () async {
        final partido = await crearPartidoAbiertoAtomica(
          firestore: firestore,
          reserva: reservaBase(),
          categoria: '6ta',
          organizadorId: 'organizador1',
          organizadorNombre: 'Organizador',
        );

        expect(partido.jugadoresIds, ['organizador1']);
        expect(partido.montoPorJugador, 1200); // 4800 / 4
        expect(partido.estado, 'Abierto');

        final reservaDoc = await firestore
            .collection('reservas_canchas')
            .doc('reserva1')
            .get();
        expect(reservaDoc.exists, isTrue);

        final ventasSnap = await firestore
            .collection('ventas_pendientes')
            .where('socio_id', isEqualTo: 'organizador1')
            .get();
        expect(ventasSnap.docs.length, 1);
        expect(
          ventasSnap.docs.first.data()['items'][0]['precio'],
          1200,
        );
      },
    );
  });

  group('unirseAPartidoAtomica', () {
    test('suma jugadores hasta completar el cupo de 4', () async {
      final partido = await crearPartidoAbiertoAtomica(
        firestore: firestore,
        reserva: reservaBase(),
        categoria: '6ta',
        organizadorId: 'j1',
        organizadorNombre: 'Jugador 1',
      );

      await unirseAPartidoAtomica(
        firestore: firestore,
        partidoId: partido.id,
        jugadorId: 'j2',
        jugadorNombre: 'Jugador 2',
      );
      await unirseAPartidoAtomica(
        firestore: firestore,
        partidoId: partido.id,
        jugadorId: 'j3',
        jugadorNombre: 'Jugador 3',
      );
      final completo = await unirseAPartidoAtomica(
        firestore: firestore,
        partidoId: partido.id,
        jugadorId: 'j4',
        jugadorNombre: 'Jugador 4',
      );

      expect(completo.jugadoresIds.length, 4);
      expect(completo.estado, 'Completo');
    });

    test('rechaza al 5to jugador cuando el partido ya está completo', () async {
      final partido = await crearPartidoAbiertoAtomica(
        firestore: firestore,
        reserva: reservaBase(),
        categoria: '6ta',
        organizadorId: 'j1',
        organizadorNombre: 'Jugador 1',
      );
      for (final j in ['j2', 'j3', 'j4']) {
        await unirseAPartidoAtomica(
          firestore: firestore,
          partidoId: partido.id,
          jugadorId: j,
          jugadorNombre: j,
        );
      }

      expect(
        () => unirseAPartidoAtomica(
          firestore: firestore,
          partidoId: partido.id,
          jugadorId: 'j5',
          jugadorNombre: 'Jugador 5',
        ),
        throwsA(isA<PartidoCompletoException>()),
      );
    });

    test('rechaza anotarse dos veces al mismo partido', () async {
      final partido = await crearPartidoAbiertoAtomica(
        firestore: firestore,
        reserva: reservaBase(),
        categoria: '6ta',
        organizadorId: 'j1',
        organizadorNombre: 'Jugador 1',
      );

      expect(
        () => unirseAPartidoAtomica(
          firestore: firestore,
          partidoId: partido.id,
          jugadorId: 'j1',
          jugadorNombre: 'Jugador 1',
        ),
        throwsA(isA<YaAnotadoEnPartidoException>()),
      );
    });

    test('cada jugador que se une genera su propia venta pendiente', () async {
      final partido = await crearPartidoAbiertoAtomica(
        firestore: firestore,
        reserva: reservaBase(),
        categoria: '6ta',
        organizadorId: 'j1',
        organizadorNombre: 'Jugador 1',
      );
      await unirseAPartidoAtomica(
        firestore: firestore,
        partidoId: partido.id,
        jugadorId: 'j2',
        jugadorNombre: 'Jugador 2',
      );

      final ventasJ2 = await firestore
          .collection('ventas_pendientes')
          .where('socio_id', isEqualTo: 'j2')
          .get();
      expect(ventasJ2.docs.length, 1);
      expect(ventasJ2.docs.first.data()['items'][0]['precio'], 1200);
    });
  });
}
