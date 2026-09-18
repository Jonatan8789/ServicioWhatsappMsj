import 'package:cloud_firestore/cloud_firestore.dart';

/// Gestiona los vínculos de "Grupo Familiar" entre socios y el descuento
/// por cantidad de integrantes que de ahí se desprende. El descuento se
/// calcula en frío a partir del tamaño del grupo (no se persiste), para que
/// nunca quede desactualizado si un integrante se da de baja.
class FamiliaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🏷️ Tramos de descuento por cantidad de integrantes activos del grupo.
  static const Map<int, double> tramosDescuento = {2: 10.0, 3: 15.0};

  double descuentoPorTamano(int cantidadIntegrantesActivos) {
    if (cantidadIntegrantesActivos >= 3) return tramosDescuento[3]!;
    if (cantidadIntegrantesActivos >= 2) return tramosDescuento[2]!;
    return 0.0;
  }

  Future<int> contarIntegrantesActivos(String grupoFamiliarId) async {
    final snap = await _firestore
        .collection('socios')
        .where('grupoFamiliarId', isEqualTo: grupoFamiliarId)
        .where('activo', isEqualTo: true)
        .get();
    return snap.docs.length;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamIntegrantes(
    String grupoFamiliarId,
  ) {
    return _firestore
        .collection('socios')
        .where('grupoFamiliarId', isEqualTo: grupoFamiliarId)
        .snapshots()
        .map((s) => s.docs);
  }

  /// Vincula dos socios al mismo grupo familiar. Si alguno ya pertenecía a
  /// un grupo, reutiliza ese grupo y migra al resto de sus integrantes para
  /// no dejar dos grupos separados apuntando a la misma familia real.
  Future<String> vincular({
    required String socioIdA,
    required String? grupoFamiliarIdA,
    required String socioIdB,
    required String? grupoFamiliarIdB,
  }) async {
    if (socioIdA == socioIdB) {
      throw Exception('No se puede vincular un socio consigo mismo.');
    }

    final String grupoId =
        grupoFamiliarIdA ??
        grupoFamiliarIdB ??
        _firestore.collection('grupos_familiares').doc().id;

    final batch = _firestore.batch();
    batch.update(_firestore.collection('socios').doc(socioIdA), {
      'grupoFamiliarId': grupoId,
    });
    batch.update(_firestore.collection('socios').doc(socioIdB), {
      'grupoFamiliarId': grupoId,
    });

    if (grupoFamiliarIdB != null && grupoFamiliarIdB != grupoId) {
      final miembrosB = await _firestore
          .collection('socios')
          .where('grupoFamiliarId', isEqualTo: grupoFamiliarIdB)
          .get();
      for (final doc in miembrosB.docs) {
        if (doc.id != socioIdB) {
          batch.update(doc.reference, {'grupoFamiliarId': grupoId});
        }
      }
    }
    if (grupoFamiliarIdA != null && grupoFamiliarIdA != grupoId) {
      final miembrosA = await _firestore
          .collection('socios')
          .where('grupoFamiliarId', isEqualTo: grupoFamiliarIdA)
          .get();
      for (final doc in miembrosA.docs) {
        if (doc.id != socioIdA) {
          batch.update(doc.reference, {'grupoFamiliarId': grupoId});
        }
      }
    }

    await batch.commit();
    return grupoId;
  }

  Future<void> desvincular(String socioId) async {
    await _firestore.collection('socios').doc(socioId).update({
      'grupoFamiliarId': FieldValue.delete(),
    });
  }
}
