import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Registro de Nota de Crédito / Débito sobre una factura de compra —
/// antes el botón "Generar NC / ND" en proveedores_compras_page.dart no
/// hacía nada (stub vacío). Una NC reduce lo que el club le debe al
/// proveedor (ej: devolución de mercadería, descuento post-facturación); una
/// ND lo aumenta (ej: interés por pago fuera de término, gasto adicional).
/// El impacto en 'cta_cte_proveedores' sigue la misma convención que ya usa
/// orden_pago_dialog.dart: montoDebe reduce el saldo que se le debe al
/// proveedor, montoHaber lo aumenta.
class NotaCreditoDebitoCompraDialog extends StatefulWidget {
  final Map<String, dynamic> factura;
  final String facturaId;

  const NotaCreditoDebitoCompraDialog({
    super.key,
    required this.factura,
    required this.facturaId,
  });

  @override
  State<NotaCreditoDebitoCompraDialog> createState() =>
      _NotaCreditoDebitoCompraDialogState();
}

class _NotaCreditoDebitoCompraDialogState
    extends State<NotaCreditoDebitoCompraDialog> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _tipo = 'NC';
  final TextEditingController _montoCtrl = TextEditingController();
  final TextEditingController _motivoCtrl = TextEditingController();
  bool _procesando = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;

    final double monto = double.parse(_montoCtrl.text.trim());
    setState(() => _procesando = true);

    try {
      final batch = _firestore.batch();

      final ncndRef = _firestore
          .collection('compras_notas_credito_debito')
          .doc();
      batch.set(ncndRef, {
        'facturaId': widget.facturaId,
        'proveedorId': widget.factura['proveedorId'],
        'cuitProveedor': widget.factura['cuitProveedor'],
        'razonSocialProveedor': widget.factura['razonSocialProveedor'],
        'tipo': _tipo,
        'monto': monto,
        'motivo': _motivoCtrl.text.trim(),
        'fecha': DateTime.now(),
        'creadoEl': FieldValue.serverTimestamp(),
      });

      batch.update(_firestore.collection('compras_facturas').doc(widget.facturaId), {
        'saldoPendiente': FieldValue.increment(_tipo == 'NC' ? -monto : monto),
      });

      final ctaCteRef = _firestore.collection('cta_cte_proveedores').doc();
      batch.set(ctaCteRef, {
        'proveedorId': widget.factura['proveedorId'],
        'cuitProveedor': widget.factura['cuitProveedor'],
        'razonSocial': widget.factura['razonSocialProveedor'],
        'fecha': DateTime.now(),
        'tipoMovimiento': _tipo == 'NC' ? 'NOTA_CREDITO' : 'NOTA_DEBITO',
        'comprobanteId': ncndRef.id,
        'descripcion':
            '${_tipo == 'NC' ? 'Nota de Crédito' : 'Nota de Débito'} s/ ${widget.factura['tipoComprobante']} N° ${widget.factura['numeroComprobante']}${_motivoCtrl.text.trim().isNotEmpty ? ' — ${_motivoCtrl.text.trim()}' : ''}',
        'montoDebe': _tipo == 'NC' ? monto : 0.0,
        'montoHaber': _tipo == 'ND' ? monto : 0.0,
      });

      await batch.commit();

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${_tipo == 'NC' ? 'Nota de Crédito' : 'Nota de Débito'} registrada.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String tipoNumComp =
        '${widget.factura['tipoComprobante'] ?? ''} ${widget.factura['numeroComprobante'] ?? ''}';
    final double saldoActual =
        (widget.factura['saldoPendiente'] as num?)?.toDouble() ??
        (widget.factura['montoTotal'] as num?)?.toDouble() ??
        0.0;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.assignment_return_rounded, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nota de Crédito / Débito — $tipoNumComp',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Proveedor: ${widget.factura['razonSocialProveedor'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Saldo pendiente actual: \$${saldoActual.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.blueGrey),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'NC',
                    label: Text('Nota de Crédito'),
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                  ButtonSegment(
                    value: 'ND',
                    label: Text('Nota de Débito'),
                    icon: Icon(Icons.add_circle_outline),
                  ),
                ],
                selected: {_tipo},
                onSelectionChanged: (sel) => setState(() => _tipo = sel.first),
              ),
              const SizedBox(height: 8),
              Text(
                _tipo == 'NC'
                    ? 'Reduce el saldo que el club le debe a este proveedor.'
                    : 'Aumenta el saldo que el club le debe a este proveedor.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  final val = double.tryParse((v ?? '').trim());
                  if (val == null || val <= 0) return 'Ingresá un monto válido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motivoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _procesando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: _procesando ? null : _confirmar,
          child: _procesando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Registrar'),
        ),
      ],
    );
  }
}
