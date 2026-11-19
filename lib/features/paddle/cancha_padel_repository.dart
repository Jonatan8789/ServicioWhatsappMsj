import 'package:cloud_firestore/cloud_firestore.dart';
import 'cancha_padel_model.dart';
import 'paddle_ids.dart';

const String coleccionCanchasPadel = 'canchas_padel';

Future<List<CanchaPadelModel>> obtenerCanchasPadel(
  FirebaseFirestore firestore,
) async {
  final snap = await firestore
      .collection(coleccionCanchasPadel)
      .orderBy('ordenVisualizacion')
      .get();
  return snap.docs
      .map((d) => CanchaPadelModel.fromFirestore(d.id, d.data()))
      .toList();
}

Future<void> guardarCanchaPadel(
  FirebaseFirestore firestore,
  CanchaPadelModel cancha,
) {
  return firestore
      .collection(coleccionCanchasPadel)
      .doc(cancha.id)
      .set(cancha.toFirestore());
}

Future<void> eliminarCanchaPadel(FirebaseFirestore firestore, String id) {
  return firestore.collection(coleccionCanchasPadel).doc(id).delete();
}

/// Lista de nombres de canchas activas para selectores/grillas. Prioriza
/// `canchas_padel` (fuente de verdad desde esta migración); si todavía no
/// se cargó ninguna cancha ahí, cae al doc plano legacy
/// (`configuracion_paddle/canchas`), y si tampoco existe, al mismo piso de
/// 3 canchas por defecto que ya usaban todas estas pantallas antes.
Future<List<String>> obtenerNombresCanchasActivas(
  FirebaseFirestore firestore,
) async {
  final canchas = await obtenerCanchasPadel(firestore);
  if (canchas.isNotEmpty) {
    return canchas.where((c) => c.activa).map((c) => c.nombre).toList();
  }

  final legacySnap = await firestore
      .collection('configuracion_paddle')
      .doc('canchas')
      .get();
  if (legacySnap.exists && legacySnap.data()?['lista'] != null) {
    return List<String>.from(legacySnap.data()!['lista']);
  }

  return const ['Cancha 1 Cristal', 'Cancha 2 Cristal', 'Cancha 3 Muro'];
}

/// Migra la lista plana vieja (`configuracion_paddle/canchas.lista`) a un
/// documento por cancha en `canchas_padel`. Idempotente: una cancha que ya
/// tenga su doc no se vuelve a pisar, así no se pierde un precio por-cancha
/// ya cargado a mano. Devuelve cuántas canchas nuevas se crearon.
Future<int> migrarCanchasLegacyACanchasPadel(FirebaseFirestore firestore) async {
  final legacySnap = await firestore
      .collection('configuracion_paddle')
      .doc('canchas')
      .get();
  final List<String> nombres = legacySnap.exists
      ? List<String>.from(legacySnap.data()?['lista'] ?? [])
      : [];

  int migradas = 0;
  for (final nombre in nombres) {
    final id = canchaSinEspacios(nombre);
    final ref = firestore.collection(coleccionCanchasPadel).doc(id);
    if ((await ref.get()).exists) continue;
    await ref.set(
      CanchaPadelModel(
        id: id,
        nombre: nombre,
        ordenVisualizacion: migradas,
      ).toFirestore(),
    );
    migradas++;
  }
  return migradas;
}
