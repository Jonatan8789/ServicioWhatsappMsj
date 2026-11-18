import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/gimnasio/clase_gimnasio_model.dart';
import 'package:natatorio_app/features/gimnasio/clase_gimnasio_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('clases_gimnasio').doc('clase1').set(
      ClaseGimnasioModel(
        id: 'clase1',
        nombre: 'Spinning',
        profesorNombre: 'Profe Juan',
        fecha: DateTime(2026, 11, 16),
        horaInicio: 18,
        cupoMaximo: 2,
      ).toFirestore(),
    );
  });

  Future<ClaseGimnasioModel> leerClase() async {
    final doc =
        await firestore.collection('clases_gimnasio').doc('clase1').get();
    return ClaseGimnasioModel.fromFirestore('clase1', doc.data()!);
  }

  group('inscribirseAClaseAtomica', () {
    test('entra directo mientras haya cupo', () async {
      final entroDirecto = await inscribirseAClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's1',
        socioNombre: 'Socio 1',
      );
      expect(entroDirecto, isTrue);

      final clase = await leerClase();
      expect(clase.inscriptosIds, ['s1']);
    });

    test('pasa a lista de espera cuando el cupo ya está lleno', () async {
      await inscribirseAClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's1',
        socioNombre: 'Socio 1',
      );
      await inscribirseAClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's2',
        socioNombre: 'Socio 2',
      );

      final entroDirecto = await inscribirseAClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's3',
        socioNombre: 'Socio 3',
      );
      expect(entroDirecto, isFalse);

      final clase = await leerClase();
      expect(clase.inscriptosIds, ['s1', 's2']);
      expect(clase.listaEsperaIds, ['s3']);
    });

    test('rechaza anotarse dos veces (ya inscripto o ya en espera)', () async {
      await inscribirseAClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's1',
        socioNombre: 'Socio 1',
      );

      expect(
        () => inscribirseAClaseAtomica(
          firestore: firestore,
          claseId: 'clase1',
          socioId: 's1',
          socioNombre: 'Socio 1',
        ),
        throwsA(isA<YaInscriptoException>()),
      );
    });
  });

  group('cancelarInscripcionClaseAtomica', () {
    test(
      'al cancelar un inscripto, promueve automáticamente al primero de la lista de espera (FIFO)',
      () async {
        await inscribirseAClaseAtomica(
          firestore: firestore,
          claseId: 'clase1',
          socioId: 's1',
          socioNombre: 'Socio 1',
        );
        await inscribirseAClaseAtomica(
          firestore: firestore,
          claseId: 'clase1',
          socioId: 's2',
          socioNombre: 'Socio 2',
        );
        await inscribirseAClaseAtomica(
          firestore: firestore,
          claseId: 'clase1',
          socioId: 's3',
          socioNombre: 'Socio 3',
        ); // lista de espera
        await inscribirseAClaseAtomica(
          firestore: firestore,
          claseId: 'clase1',
          socioId: 's4',
          socioNombre: 'Socio 4',
        ); // lista de espera, detrás de s3

        await cancelarInscripcionClaseAtomica(
          firestore: firestore,
          claseId: 'clase1',
          socioId: 's1',
        );

        final clase = await leerClase();
        expect(clase.inscriptosIds, ['s2', 's3']); // s3 promovido, no s4
        expect(clase.listaEsperaIds, ['s4']);
      },
    );

    test('cancelar desde la lista de espera no promueve a nadie', () async {
      await inscribirseAClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's1',
        socioNombre: 'Socio 1',
      );
      await inscribirseAClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's2',
        socioNombre: 'Socio 2',
      );
      await inscribirseAClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's3',
        socioNombre: 'Socio 3',
      ); // lista de espera

      await cancelarInscripcionClaseAtomica(
        firestore: firestore,
        claseId: 'clase1',
        socioId: 's3',
      );

      final clase = await leerClase();
      expect(clase.inscriptosIds, ['s1', 's2']);
      expect(clase.listaEsperaIds, isEmpty);
    });
  });
}
