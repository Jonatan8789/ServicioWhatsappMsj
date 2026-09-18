import 'package:cloud_firestore/cloud_firestore.dart';

/// 🚨 Antes no existía ningún registro histórico de movimientos de stock: el
/// POS y la edición manual sólo hacían FieldValue.increment/update directo
/// sobre 'stockActual', así que no había forma de auditar "por qué bajó el
/// stock de este producto" más allá de mirar el número actual. Este servicio
/// deja una traza en 'movimientos_stock' cada vez que el stock cambia.
class MovimientoStockService {
  MovimientoStockService._();

  static Future<void> registrarMovimiento({
    required String productoId,
    required String productoNombre,
    required String tipo, // 'Venta POS' | 'Ajuste Manual' | 'Alta Inicial'
    required int cantidad, // negativo = baja, positivo = alta
    String? referencia,
    String? usuario,
  }) async {
    if (cantidad == 0) return;
    await FirebaseFirestore.instance.collection('movimientos_stock').add({
      'productoId': productoId,
      'productoNombre': productoNombre,
      'tipo': tipo,
      'cantidad': cantidad,
      'referencia': referencia,
      'usuario': usuario,
      'fecha': FieldValue.serverTimestamp(),
    });
  }

  /// Variante para usar DENTRO de un WriteBatch ya existente (POS), para que
  /// el movimiento quede atómico junto con la venta y el descuento de stock.
  static void registrarMovimientoEnBatch(
    WriteBatch batch, {
    required String productoId,
    required String productoNombre,
    required String tipo,
    required int cantidad,
    String? referencia,
    String? usuario,
  }) {
    if (cantidad == 0) return;
    final ref = FirebaseFirestore.instance.collection('movimientos_stock').doc();
    batch.set(ref, {
      'productoId': productoId,
      'productoNombre': productoNombre,
      'tipo': tipo,
      'cantidad': cantidad,
      'referencia': referencia,
      'usuario': usuario,
      'fecha': FieldValue.serverTimestamp(),
    });
  }
}
