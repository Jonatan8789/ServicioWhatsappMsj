import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Registro centralizado de operaciones sensibles — antes no existía
/// ninguno de verdad ('auditoria_movimientos_caja' estaba en las reglas
/// pero nada la escribía). La colección 'auditoria_sistema' es create-only
/// (ver firestore.rules): ni un admin puede editar o borrar un asiento ya
/// escrito.
Future<void> registrarAuditoria({
  required String accion,
  required String entidad,
  String? entidadId,
  Map<String, dynamic>? detalle,
}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('auditoria_sistema').add({
      'accion': accion,
      'entidad': entidad,
      'entidadId': entidadId,
      'detalle': detalle ?? {},
      'uid': user?.uid,
      'email': user?.email,
      'fecha': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // La auditoría nunca debe romper la operación principal que la disparó.
  }
}
