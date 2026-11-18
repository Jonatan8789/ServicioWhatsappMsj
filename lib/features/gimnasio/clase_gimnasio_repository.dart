import 'package:cloud_firestore/cloud_firestore.dart';
import 'clase_gimnasio_model.dart';

class YaInscriptoException implements Exception {
  final String message;
  YaInscriptoException([
    this.message = 'Ya estás anotado en esta clase (o en su lista de espera).',
  ]);
  @override
  String toString() => message;
}

/// Inscribe a un socio en una clase: si hay cupo, entra directo; si no,
/// se anota al final de la lista de espera (FIFO). Todo dentro de una
/// transacción para que dos inscripciones casi simultáneas nunca pisen el
/// mismo último lugar ni dupliquen a la misma persona en ambas listas.
///
/// Devuelve `true` si entró directo a la clase, `false` si quedó en lista
/// de espera.
Future<bool> inscribirseAClaseAtomica({
  required FirebaseFirestore firestore,
  required String claseId,
  required String socioId,
  required String socioNombre,
}) async {
  final claseRef = firestore.collection('clases_gimnasio').doc(claseId);
  late bool entroDirecto;

  await firestore.runTransaction((transaction) async {
    final snap = await transaction.get(claseRef);
    if (!snap.exists) throw Exception('Esa clase ya no existe.');
    final clase = ClaseGimnasioModel.fromFirestore(snap.id, snap.data()!);

    if (clase.inscriptosIds.contains(socioId) ||
        clase.listaEsperaIds.contains(socioId)) {
      throw YaInscriptoException();
    }

    if (clase.inscriptosIds.length < clase.cupoMaximo) {
      entroDirecto = true;
      transaction.update(claseRef, {
        'inscriptosIds': [...clase.inscriptosIds, socioId],
        'inscriptosNombres': [...clase.inscriptosNombres, socioNombre],
      });
    } else {
      entroDirecto = false;
      transaction.update(claseRef, {
        'listaEsperaIds': [...clase.listaEsperaIds, socioId],
        'listaEsperaNombres': [...clase.listaEsperaNombres, socioNombre],
      });
    }
  });

  return entroDirecto;
}

/// Cancela la inscripción (o el lugar en lista de espera) de un socio. Si
/// salía de los inscriptos efectivos y había alguien esperando, promueve
/// automáticamente al primero de la lista de espera (FIFO) al cupo que
/// quedó libre, todo en la misma transacción.
Future<void> cancelarInscripcionClaseAtomica({
  required FirebaseFirestore firestore,
  required String claseId,
  required String socioId,
}) async {
  final claseRef = firestore.collection('clases_gimnasio').doc(claseId);

  await firestore.runTransaction((transaction) async {
    final snap = await transaction.get(claseRef);
    if (!snap.exists) return;
    final clase = ClaseGimnasioModel.fromFirestore(snap.id, snap.data()!);

    final int idxInscripto = clase.inscriptosIds.indexOf(socioId);
    if (idxInscripto != -1) {
      final nuevosInscriptosIds = [...clase.inscriptosIds]
        ..removeAt(idxInscripto);
      final nuevosInscriptosNombres = [...clase.inscriptosNombres]
        ..removeAt(idxInscripto);
      List<String> nuevaEsperaIds = clase.listaEsperaIds;
      List<String> nuevaEsperaNombres = clase.listaEsperaNombres;

      if (nuevaEsperaIds.isNotEmpty) {
        nuevosInscriptosIds.add(nuevaEsperaIds.first);
        nuevosInscriptosNombres.add(nuevaEsperaNombres.first);
        nuevaEsperaIds = nuevaEsperaIds.sublist(1);
        nuevaEsperaNombres = nuevaEsperaNombres.sublist(1);
      }

      transaction.update(claseRef, {
        'inscriptosIds': nuevosInscriptosIds,
        'inscriptosNombres': nuevosInscriptosNombres,
        'listaEsperaIds': nuevaEsperaIds,
        'listaEsperaNombres': nuevaEsperaNombres,
      });
      return;
    }

    final int idxEspera = clase.listaEsperaIds.indexOf(socioId);
    if (idxEspera != -1) {
      final nuevaEsperaIds = [...clase.listaEsperaIds]..removeAt(idxEspera);
      final nuevaEsperaNombres = [...clase.listaEsperaNombres]
        ..removeAt(idxEspera);
      transaction.update(claseRef, {
        'listaEsperaIds': nuevaEsperaIds,
        'listaEsperaNombres': nuevaEsperaNombres,
      });
    }
  });
}
