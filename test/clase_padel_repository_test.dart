import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/paddle/clase_padel_model.dart';
import 'package:natatorio_app/features/paddle/clase_padel_repository.dart';
import 'package:natatorio_app/features/paddle/reserva_cancha_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<ClasePadelModel> crearClase({
    int cupoMaximo = 2,
    double precioPorAlumno = 3000,
    int horaInicio = 18,
    String cancha = 'Cancha 1 Cristal',
  }) {
    return crearClasePadelAtomica(
      firestore: firestore,
      nombre: 'Clase Intermedio',
      profesorId: 'profe1',
      profesorNombre: 'Profe Juan',
      cancha: cancha,
      fecha: DateTime(2026, 11, 16),
      horaInicio: horaInicio,
      duracionHoras: 1,
      cupoMaximo: cupoMaximo,
      precioPorAlumno: precioPorAlumno,
      creadoPor: 'admin1',
    );
  }

  Future<ClasePadelModel> leerClase(String id) async {
    final doc = await firestore.collection('clases_padel').doc(id).get();
    return ClasePadelModel.fromFirestore(id, doc.data()!);
  }

  Future<PagoClasePadelModel?> leerPago(String claseId, String socioId) async {
    final doc = await firestore
        .collection('pagos_clases_padel')
        .doc('${claseId}_$socioId')
        .get();
    if (!doc.exists) return null;
    return PagoClasePadelModel.fromFirestore(doc.id, doc.data()!);
  }

  // En los tests, 'ventaSocioId' siempre es el mismo socioId (no hace
  // falta distinguir auth.uid vs. socios/{id} fuera de las reglas reales).
  Future<bool> inscribir(String claseId, String socioId, String socioNombre) {
    return inscribirseAClasePadelAtomica(
      firestore: firestore,
      claseId: claseId,
      socioId: socioId,
      socioNombre: socioNombre,
      ventaSocioId: socioId,
    );
  }

  group('crearClasePadelAtomica', () {
    test('crea la clase y bloquea la cancha (reserva + slot)', () async {
      final clase = await crearClase();

      final reserva = await firestore
          .collection('reservas_canchas')
          .doc(clase.reservaId)
          .get();
      expect(reserva.exists, isTrue);
      expect(reserva.data()!['nombreCliente'], contains('Clase Intermedio'));

      final slot = await firestore
          .collection('reservas_canchas_slots')
          .doc('2026-11-16_Cancha1Cristal_18hs')
          .get();
      expect(slot.exists, isTrue);
    });

    test(
      'falla si la cancha ya estaba ocupada a esa hora (no crea la clase)',
      () async {
        await crearClase();

        expect(
          () => crearClase(),
          throwsA(isA<HorarioOcupadoException>()),
        );

        final clases = await firestore.collection('clases_padel').get();
        expect(clases.docs.length, 1);
      },
    );
  });

  group('inscribirseAClasePadelAtomica', () {
    test(
      'entra directo mientras haya cupo y genera pago + venta pendiente',
      () async {
        final clase = await crearClase(precioPorAlumno: 3000);

        final entroDirecto = await inscribir(clase.id, 's1', 'Socio 1');
        expect(entroDirecto, isTrue);

        final actualizada = await leerClase(clase.id);
        expect(actualizada.inscriptosIds, ['s1']);

        final pago = await leerPago(clase.id, 's1');
        expect(pago, isNotNull);
        expect(pago!.monto, 3000);
        expect(pago.estaPago, isFalse);
        expect(pago.ventaPendienteId, isNotNull);

        final venta = await firestore
            .collection('ventas_pendientes')
            .doc(pago.ventaPendienteId)
            .get();
        expect(venta.exists, isTrue);
        expect(venta.data()!['socio_id'], 's1');
      },
    );

    test(
      'pasa a lista de espera sin generar pago cuando el cupo está lleno',
      () async {
        final clase = await crearClase(cupoMaximo: 1);
        await inscribir(clase.id, 's1', 'Socio 1');

        final entroDirecto = await inscribir(clase.id, 's2', 'Socio 2');
        expect(entroDirecto, isFalse);

        final actualizada = await leerClase(clase.id);
        expect(actualizada.listaEsperaIds, ['s2']);

        final pago = await leerPago(clase.id, 's2');
        expect(pago, isNull);
      },
    );

    test('rechaza anotarse dos veces a la misma clase', () async {
      final clase = await crearClase();
      await inscribir(clase.id, 's1', 'Socio 1');

      expect(
        () => inscribir(clase.id, 's1', 'Socio 1'),
        throwsA(isA<YaInscriptoEnClasePadelException>()),
      );
    });
  });

  group('cancelarInscripcionClasePadelAtomica', () {
    test(
      'promueve de la lista de espera (FIFO) y recién ahí genera su pago',
      () async {
        final clase = await crearClase(cupoMaximo: 1);
        await inscribir(clase.id, 's1', 'Socio 1');
        await inscribir(clase.id, 's2', 'Socio 2'); // lista de espera

        await cancelarInscripcionClasePadelAtomica(
          firestore: firestore,
          claseId: clase.id,
          socioId: 's1',
        );

        final actualizada = await leerClase(clase.id);
        expect(actualizada.inscriptosIds, ['s2']);
        expect(actualizada.listaEsperaIds, isEmpty);

        final pagoS2 = await leerPago(clase.id, 's2');
        expect(pagoS2, isNotNull);
        expect(pagoS2!.monto, clase.precioPorAlumno);
      },
    );

    test(
      'borra el pago pendiente del que se da de baja (todavía no había pagado)',
      () async {
        final clase = await crearClase();
        await inscribir(clase.id, 's1', 'Socio 1');

        await cancelarInscripcionClasePadelAtomica(
          firestore: firestore,
          claseId: clase.id,
          socioId: 's1',
        );

        final pago = await leerPago(clase.id, 's1');
        expect(pago, isNull);
      },
    );

    test(
      'si el pago ya estaba cobrado, no lo borra al cancelar (queda como histórico)',
      () async {
        final clase = await crearClase();
        await inscribir(clase.id, 's1', 'Socio 1');
        await firestore
            .collection('pagos_clases_padel')
            .doc('${clase.id}_s1')
            .update({'cobrado': true});

        await cancelarInscripcionClasePadelAtomica(
          firestore: firestore,
          claseId: clase.id,
          socioId: 's1',
        );

        final pago = await leerPago(clase.id, 's1');
        expect(pago, isNotNull);
        expect(pago!.cobrado, isTrue);
      },
    );

    test('cancelar desde la lista de espera no promueve a nadie', () async {
      final clase = await crearClase(cupoMaximo: 1);
      await inscribir(clase.id, 's1', 'Socio 1');
      await inscribir(clase.id, 's2', 'Socio 2'); // lista de espera

      await cancelarInscripcionClasePadelAtomica(
        firestore: firestore,
        claseId: clase.id,
        socioId: 's2',
      );

      final actualizada = await leerClase(clase.id);
      expect(actualizada.inscriptosIds, ['s1']);
      expect(actualizada.listaEsperaIds, isEmpty);
    });
  });
}
