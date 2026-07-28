import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/datos_socios_oqua.dart';

class MigracionService {
  static Future<bool> ejecutarMigracion() async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      final totalSocios = DatosOqua.socios.length;
      print(
        '🚀 Iniciando proceso de migración. Total de socios encontrados en archivo: $totalSocios',
      );

      if (totalSocios == 0) {
        print('⚠️ ATENCIÓN: La lista DatosOqua.socios está vacía.');
        return false;
      }

      const int tamanoLote = 300;

      for (var i = 0; i < totalSocios; i += tamanoLote) {
        final WriteBatch batch = db.batch();
        final fin = (i + tamanoLote < totalSocios)
            ? i + tamanoLote
            : totalSocios;
        final sublista = DatosOqua.socios.sublist(i, fin);

        for (var socioMap in sublista) {
          final String id = socioMap['id'] ?? db.collection('socios').doc().id;
          final DocumentReference docRef = db.collection('socios').doc(id);
          batch.set(docRef, socioMap, SetOptions(merge: true));
        }

        print('📦 Guardando lote de socio $i a ${fin - 1} en Firestore...');
        await batch.commit();
      }

      print(
        '✅ Migración finalizada con éxito. Se procesaron $totalSocios registros.',
      );
      return true;
    } catch (e) {
      print('❌ ERROR CRÍTICO EN LA MIGRACIÓN: $e');
      rethrow;
    }
  }
}
