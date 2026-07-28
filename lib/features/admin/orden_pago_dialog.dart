import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class OrdenPagoDialog extends StatefulWidget {
  final Map<String, dynamic> factura;
  final String facturaId;

  const OrdenPagoDialog({
    super.key,
    required this.factura,
    required this.facturaId,
  });

  @override
  State<OrdenPagoDialog> createState() => _OrdenPagoDialogState();
}

class _OrdenPagoDialogState extends State<OrdenPagoDialog> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late double _saldoPendiente;
  late double _montoAPagar;
  String _medioPago = 'Transferencia Bancaria';
  String _referenciaComprobante = ''; // N° de transferencia o N° de Cheque
  DateTime _fechaPago = DateTime.now();

  @override
  void initState() {
    super.initState();
    _saldoPendiente = (widget.factura['saldoPendiente'] as num?)?.toDouble() ??
        (widget.factura['montoTotal'] as num?)?.toDouble() ??
        0.0;
    _montoAPagar = _saldoPendiente;
  }

  @override
  Widget build(BuildContext context) {
    final razonSocial = widget.factura['razonSocialProveedor'] ?? 'Proveedor';
    final tipoNumComp =
        '${widget.factura['tipoComprobante']} ${widget.factura['numeroComprobante']}';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.payments_rounded, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Emitir Orden de Pago - $tipoNumComp',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ℹ️ RESUMEN DEL COMPROBANTE Y DETALLES BANCARIOS
                _buildInfoCard(razonSocial),
                const SizedBox(height: 16),

                // 💵 MONTO A PAGAR
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _saldoPendiente.toStringAsFixed(2),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Monto a Cancelar',
                          prefixText: '\$ ',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final val = double.tryParse(v ?? '');
                          if (val == null || val <= 0) return 'Monto inválido';
                          if (val > _saldoPendiente + 0.01) {
                            return 'Excede el saldo (\$${_saldoPendiente.toStringAsFixed(2)})';
                          }
                          return null;
                        },
                        onChanged: (v) =>
                            _montoAPagar = double.tryParse(v) ?? 0.0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade100,
                        foregroundColor: Colors.black87,
                      ),
                      onPressed: () {
                        setState(() {
                          _montoAPagar = _saldoPendiente;
                        });
                      },
                      child: const Text('Pago Total'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 💳 MEDIO DE PAGO & REFERENCIA
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _medioPago,
                        decoration: const InputDecoration(
                          labelText: 'Medio de Pago',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          'Transferencia Bancaria',
                          'Efectivo (Caja Chica)',
                          'ECHEQ / Cheque Propio',
                          'Tarjeta Corporativa'
                        ]
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) => setState(() => _medioPago = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'N° Recibo / Ref. Transacción',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => _referenciaComprobante = v.trim(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 📅 FECHA DE EMISIÓN
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(
                      'Fecha de Pago: ${DateFormat('dd/MM/yyyy').format(_fechaPago)}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fechaPago,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setState(() => _fechaPago = picked);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _procesarOrdenDePago,
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text('Confirmar Orden de Pago',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // Tarjeta informativa del proveedor y la deuda
  Widget _buildInfoCard(String razonSocial) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(razonSocial,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              Text('CUIT: ${widget.factura['cuitProveedor'] ?? '-'}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monto Original: \$${(widget.factura['montoTotal'] as num).toStringAsFixed(2)}'),
              Text(
                'Saldo Pendiente: \$${_saldoPendiente.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Executar procesamiento atómico en Firestore
  Future<void> _procesarOrdenDePago() async {
    if (!_formKey.currentState!.validate()) return;

    final batch = _firestore.batch();

    // 1. Calcular nuevo saldo
    final double nuevoSaldo = _saldoPendiente - _montoAPagar;
    final String nuevoEstado = nuevoSaldo <= 0.01 ? 'PAGADO' : 'PARCIAL';

    // 2. Actualizar la factura
    final facturaRef =
        _firestore.collection('compras_facturas').doc(widget.facturaId);
    batch.update(facturaRef, {
      'saldoPendiente': nuevoSaldo < 0 ? 0.0 : nuevoSaldo,
      'estadoPago': nuevoEstado,
      'ultimoPagoFecha': Timestamp.fromDate(_fechaPago),
    });

    // 3. Crear el documento de la Orden de Pago (OP)
    final opRef = _firestore.collection('compras_ordenes_pago').doc();
    batch.set(opRef, {
      'facturaId': widget.facturaId,
      'proveedorId': widget.factura['proveedorId'],
      'razonSocialProveedor': widget.factura['razonSocialProveedor'],
      'cuitProveedor': widget.factura['cuitProveedor'],
      'montoPagado': _montoAPagar,
      'medioPago': _medioPago,
      'referenciaComprobante': _referenciaComprobante,
      'fechaPago': Timestamp.fromDate(_fechaPago),
      'creadoEl': FieldValue.serverTimestamp(),
    });

    // 4. Imputar movimiento en la Cuenta Corriente del Proveedor (Debe -> Cancela deuda)
    final ctaCteRef = _firestore.collection('cta_cte_proveedores').doc();
    batch.set(ctaCteRef, {
      'proveedorId': widget.factura['proveedorId'],
      'cuitProveedor': widget.factura['cuitProveedor'],
      'razonSocial': widget.factura['razonSocialProveedor'],
      'fecha': Timestamp.fromDate(_fechaPago),
      'tipoMovimiento': 'ORDEN_PAGO',
      'comprobanteId': opRef.id,
      'descripcion':
          'Pago de ${widget.factura['tipoComprobante']} N° ${widget.factura['numeroComprobante']} - Ref: $_referenciaComprobante',
      'montoDebe': _montoAPagar, // Reduce el saldo acreedor
      'montoHaber': 0.0,
    });

    // 5. Impactar Egreso en Tesorería
    final cajaRef = _firestore.collection('caja_movimientos').doc();
    batch.set(cajaRef, {
      'tipo': 'EGRESO',
      'categoria': 'Pago a Proveedores',
      'monto': _montoAPagar,
      'medioPago': _medioPago,
      'concepto':
          'Pago a ${widget.factura['razonSocialProveedor']} (${widget.factura['tipoComprobante']} N° ${widget.factura['numeroComprobante']})',
      'fecha': Timestamp.fromDate(_fechaPago),
      'referenciaId': opRef.id,
    });

    await batch.commit();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Orden de Pago emitida exitosamente. Estado: $nuevoEstado'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}