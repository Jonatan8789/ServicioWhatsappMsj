import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/paddle/cancha_padel_model.dart';
import 'package:natatorio_app/features/paddle/cancha_padel_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('obtenerNombresCanchasActivas', () {
    test(
      'usa canchas_padel cuando hay canchas cargadas, excluyendo las inactivas',
      () async {
        await guardarCanchaPadel(
          firestore,
          const CanchaPadelModel(id: 'CanchaA', nombre: 'Cancha A'),
        );
        await guardarCanchaPadel(
          firestore,
          const CanchaPadelModel(
            id: 'CanchaB',
            nombre: 'Cancha B',
            activa: false,
          ),
        );

        final nombres = await obtenerNombresCanchasActivas(firestore);
        expect(nombres, ['Cancha A']);
      },
    );

    test(
      'cae a la lista legacy (configuracion_paddle/canchas) si no hay nada en canchas_padel',
      () async {
        await firestore.collection('configuracion_paddle').doc('canchas').set({
          'lista': ['Cancha Vieja 1', 'Cancha Vieja 2'],
        });

        final nombres = await obtenerNombresCanchasActivas(firestore);
        expect(nombres, ['Cancha Vieja 1', 'Cancha Vieja 2']);
      },
    );

    test(
      'cae a los 3 nombres por defecto si no hay ni canchas_padel ni legacy',
      () async {
        final nombres = await obtenerNombresCanchasActivas(firestore);
        expect(nombres, [
          'Cancha 1 Cristal',
          'Cancha 2 Cristal',
          'Cancha 3 Muro',
        ]);
      },
    );
  });

  group('migrarCanchasLegacyACanchasPadel', () {
    test('migra cada nombre de la lista legacy a un doc propio', () async {
      await firestore.collection('configuracion_paddle').doc('canchas').set({
        'lista': ['Cancha 1 Cristal', 'Cancha 2 Cristal'],
      });

      final migradas = await migrarCanchasLegacyACanchasPadel(firestore);
      expect(migradas, 2);

      final canchas = await obtenerCanchasPadel(firestore);
      expect(canchas.map((c) => c.nombre).toList(), [
        'Cancha 1 Cristal',
        'Cancha 2 Cristal',
      ]);
    });

    test(
      'es idempotente: no pisa una cancha que ya tenga precio propio cargado',
      () async {
        await firestore.collection('configuracion_paddle').doc('canchas').set({
          'lista': ['Cancha 1 Cristal'],
        });
        await guardarCanchaPadel(
          firestore,
          const CanchaPadelModel(
            id: 'Cancha1Cristal',
            nombre: 'Cancha 1 Cristal',
            precioBaseHoraSocio: 9999,
          ),
        );

        final migradas = await migrarCanchasLegacyACanchasPadel(firestore);
        expect(migradas, 0);

        final canchas = await obtenerCanchasPadel(firestore);
        expect(canchas.single.precioBaseHoraSocio, 9999);
      },
    );
  });
}
