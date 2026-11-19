import 'package:cloud_firestore/cloud_firestore.dart';

/// Medios de pago manuales que se asientan directo en una caja física
/// abierta (ver `control_cajas` / `CajaTurnoModel`). 'Cuenta Corriente' no
/// entra acá (no toca caja física) y 'Mercado Pago' se cobra por su propio
/// flujo online (`mostrarSelectorCobroMercadoPago`), no por esta suma manual.
const List<String> mediosPagoManualCaja = [
  'Efectivo ARS',
  'Transferencia',
  'Tarjeta Débito',
  'Tarjeta Crédito',
  'MODO',
];

String campoControlCajaPara(String medioPago) {
  switch (medioPago) {
    case 'Efectivo ARS':
    case 'Efectivo':
      return 'totalEfectivoARS';
    case 'Transferencia':
      return 'totalTransferencia';
    case 'Tarjeta Débito':
      return 'totalTarjetaDebito';
    case 'Tarjeta Crédito':
      return 'totalTarjetaCredito';
    case 'MODO':
      return 'totalModo';
    case 'Mercado Pago':
      return 'totalMercadoPago';
    default:
      return 'totalEfectivoARS';
  }
}

/// Nombres de terminal con una caja actualmente abierta (`estado=='Abierta'`)
/// — mismo criterio por terminal que usa `pos_caja_page.dart`
/// (`nombreCajaTerminal`), el que ya se corrigió en `canchas_page.dart`
/// (antes buscaba por un nombre de usuario fijo que no existía).
Future<List<String>> terminalesConCajaAbierta(
  FirebaseFirestore firestore,
) async {
  final snap = await firestore
      .collection('control_cajas')
      .where('estado', isEqualTo: 'Abierta')
      .get();
  return snap.docs
      .map((d) => (d.data()['nombreCajaTerminal'] as String?) ?? '')
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList();
}

/// Suma `monto` al canal correspondiente de la caja abierta en `terminal`.
/// Devuelve `true` si encontró esa caja y sumó el monto, `false` si no
/// (p. ej. se cerró justo antes de confirmar).
Future<bool> sumarACajaAbierta(
  FirebaseFirestore firestore, {
  required String terminal,
  required String medioPago,
  required double monto,
}) async {
  final cajaQuery = await firestore
      .collection('control_cajas')
      .where('nombreCajaTerminal', isEqualTo: terminal)
      .where('estado', isEqualTo: 'Abierta')
      .limit(1)
      .get();
  if (cajaQuery.docs.isEmpty) return false;
  await firestore
      .collection('control_cajas')
      .doc(cajaQuery.docs.first.id)
      .update({campoControlCajaPara(medioPago): FieldValue.increment(monto)});
  return true;
}
