import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/datos_socios_oqua.dart';

class MigracionService {
  // 🚨 El esquema vivo (SocioModel/socio_login_page.dart/liquidacion_cuotas_service.dart)
  // espera 'deporte' (no 'categoria') y 'dni' como String de login. Este
  // transform corrige lo que SÍ está en el archivo fuente. Lo que NO está en
  // ninguna de las 609 entradas — 'dni' y 'frecuencia' — no se puede inventar
  // acá: hace falta la planilla real del club con esos datos por socio antes
  // de poder cerrar el login por DNI y la facturación automática para estos
  // registros migrados.
  static Map<String, dynamic> _normalizarSocio(Map<String, dynamic> raw) {
    final Map<String, dynamic> normalizado = Map<String, dynamic>.from(raw);

    if (normalizado.containsKey('categoria')) {
      normalizado['deporte'] = normalizado.remove('categoria');
    }

    return normalizado;
  }

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

      final int sinDni = DatosOqua.socios
          .where((s) => !s.containsKey('dni'))
          .length;
      if (sinDni > 0) {
        print(
          '⚠️ ATENCIÓN: $sinDni de $totalSocios socios no tienen \'dni\' en el '
          'archivo fuente. Esos socios NO van a poder iniciar sesión en el '
          'portal (que loguea por DNI) hasta que se cargue ese dato.',
        );
      }

      const int tamanoLote = 300;

      for (var i = 0; i < totalSocios; i += tamanoLote) {
        final WriteBatch batch = db.batch();
        final fin = (i + tamanoLote < totalSocios)
            ? i + tamanoLote
            : totalSocios;
        final sublista = DatosOqua.socios.sublist(i, fin);

        for (var socioMap in sublista) {
          final Map<String, dynamic> normalizado = _normalizarSocio(socioMap);
          final String id =
              normalizado['id'] ?? db.collection('socios').doc().id;
          final DocumentReference docRef = db.collection('socios').doc(id);
          batch.set(docRef, normalizado, SetOptions(merge: true));
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
