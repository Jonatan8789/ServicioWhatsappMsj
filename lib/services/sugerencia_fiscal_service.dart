/// Sugiere si un cobro debería facturarse por ARCA (comprobante fiscal real,
/// CAE) o quedar como comprobante interno no fiscal ("Factura X"), a partir
/// del medio de pago elegido. Regla del club: todo lo que se cobra por un
/// medio electrónico se factura con ARCA (una vez constituida la SRL, con
/// Factura A/B real); todo lo que se cobra en efectivo queda como X.
/// Es sólo una sugerencia — el toggle "Emitir Factura Fiscal" en cada
/// pantalla sigue siendo editable a mano por el operador.
bool esMedioPagoElectronico(String medioPago) {
  final String m = medioPago.toLowerCase();
  if (m.contains('efectivo')) return false;
  if (m.contains('cuenta corriente')) {
    // Todavía no hay un cobro real: se factura recién cuando esa cuenta
    // corriente se salda de verdad (ver cobro_manual_adelantado_dialog.dart).
    return false;
  }
  return m.contains('mercado pago') ||
      m.contains('tarjeta') ||
      m.contains('transferencia') ||
      m.contains('qr');
}
