import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CobroManualAdelantadoDialog extends StatefulWidget {
  final String socioId;
  final String nombreSocio;
  final double montoSugerido;

  const CobroManualAdelantadoDialog({
    super.key,
    required this.socioId,
    required this.nombreSocio,
    required this.montoSugerido,
  });

  @override
  State<CobroManualAdelantadoDialog> createState() =>
      _CobroManualAdelantadoDialogState();
}

class _CobroManualAdelantadoDialogState
    extends State<CobroManualAdelantadoDialog> {
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _montoCtrl;
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;
  String _medioPago = 'Efectivo';
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _montoCtrl = TextEditingController(
      text: widget.montoSugerido.toStringAsFixed(2),
    );
  }

  Future<void> _procesarCobroAdelantado() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _procesando = true);

    final String periodo =
        "$_anioSeleccionado-${_mesSeleccionado.toString().padLeft(2, '0')}";
    final double monto = double.parse(_montoCtrl.text);

    try {
      final batch = _firestore.batch();

      // 1. Crear el registro en la Cuenta Corriente del Socio como PAGADO
      final ctaCteRef = _firestore
          .collection('socios')
          .doc(widget.socioId)
          .collection('cuenta_corriente')
          .doc();

      batch.set(ctaCteRef, {
        'fecha': DateTime.now(),
        'tipo': 'Cobro Manual Adelantado',
        'periodo':
            periodo, // 👈 Clave para que el facturador masivo lo detecte y omita
        'concepto': 'Pago Adelantado Cuota $periodo',
        'monto': monto,
        'estado': 'Pagado',
        'medioPago': _medioPago,
        'origen': 'RECEPCION_MANUAL',
      });

      // 2. Registrar el Ingreso en la Caja Chica/Diaria
      final cajaRef = _firestore.collection('caja_movimientos').doc();
      batch.set(cajaRef, {
        'tipo': 'INGRESO',
        'categoria': 'Cobro Cuota Adelantada',
        'monto': monto,
        'medioPago': _medioPago,
        'concepto': 'Cobro cuota $periodo - ${widget.nombreSocio}',
        'fecha': DateTime.now(),
        'socioId': widget.socioId,
      });

      await batch.commit();

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Cobro registrado y cuota saldada.'),
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
    return AlertDialog(
      title: Text('Cobro Manual / Adelantado - ${widget.nombreSocio}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _mesSeleccionado,
                    decoration: const InputDecoration(labelText: 'Mes'),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('Mes ${i + 1}'),
                      ),
                    ),
                    onChanged: (v) => setState(() => _mesSeleccionado = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _anioSeleccionado,
                    decoration: const InputDecoration(labelText: 'Año'),
                    items: [2026, 2027]
                        .map(
                          (a) => DropdownMenuItem(value: a, child: Text('$a')),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _anioSeleccionado = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto a Cobrar',
                prefixText: '\$ ',
              ),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _medioPago,
              decoration: const InputDecoration(labelText: 'Medio de Pago'),
              items: [
                'Efectivo',
                'Mercado Pago / QR',
                'Transferencia',
                'Tarjeta',
              ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setState(() => _medioPago = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _procesando ? null : _procesarCobroAdelantado,
          child: _procesando
              ? const CircularProgressIndicator()
              : const Text('Registrar Cobro'),
        ),
      ],
    );
  }
}
