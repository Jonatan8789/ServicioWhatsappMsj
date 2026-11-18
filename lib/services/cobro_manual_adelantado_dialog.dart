import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'sugerencia_fiscal_service.dart';
import '../shared/mercado_pago_dialog.dart';

class CobroManualAdelantadoDialog extends StatefulWidget {
  final String socioId;
  final String nombreSocio;
  final String dniSocio;
  final double montoSugerido;

  const CobroManualAdelantadoDialog({
    super.key,
    required this.socioId,
    required this.nombreSocio,
    required this.dniSocio,
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
  bool _emitirFacturaFiscal = false;

  @override
  void initState() {
    super.initState();
    _montoCtrl = TextEditingController(
      text: widget.montoSugerido.toStringAsFixed(2),
    );
    _emitirFacturaFiscal = esMedioPagoElectronico(_medioPago);
  }

  Future<void> _procesarCobroAdelantado() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _procesando = true);

    final String periodo =
        "$_anioSeleccionado-${_mesSeleccionado.toString().padLeft(2, '0')}";
    final double monto = double.parse(_montoCtrl.text);

    try {
      // 🧾 Facturación ARCA: se emite ACÁ, al momento del cobro efectivo —
      // no en la liquidación masiva — porque recién acá hay un pago real
      // para respaldar el CAE. Se pide antes del batch porque si ARCA
      // falla, se sigue registrando el cobro igual (como comprobante no
      // fiscal), tal como ya hace pos_caja_page.dart con las ventas.
      String? caeFactura;
      String? vencimientoCaeFactura;
      num? nroFacturaLegal;
      num? puntoVentaLegal;
      num? tipoComprobanteLegal;
      if (_emitirFacturaFiscal) {
        try {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'emitirFacturaArca',
          );
          final String periodoDesde =
              "$_anioSeleccionado${_mesSeleccionado.toString().padLeft(2, '0')}01";
          final DateTime ultimoDiaMes = DateTime(
            _anioSeleccionado,
            _mesSeleccionado + 1,
            0,
          );
          final String periodoHasta =
              "$_anioSeleccionado${_mesSeleccionado.toString().padLeft(2, '0')}${ultimoDiaMes.day.toString().padLeft(2, '0')}";
          final resp = await callable.call({
            'total': monto,
            'socioDni': widget.dniSocio,
            'concepto': 2, // Servicio (cuota social)
            'periodoDesde': periodoDesde,
            'periodoHasta': periodoHasta,
          });
          if (resp.data['success'] == true) {
            // 🚨 Antes sólo se guardaba el CAE y se descartaba el resto de
            // la respuesta (N° de factura, punto de venta, vencimiento) —
            // igual bug que ya se había corregido en pos_caja_page.dart.
            // Sin esto, el Libro IVA / export CITI no puede reconstruir el
            // número de comprobante real de una cuota facturada.
            caeFactura = resp.data['cae'];
            vencimientoCaeFactura = resp.data['vencimientoCae'];
            nroFacturaLegal = resp.data['nroFactura'];
            puntoVentaLegal = resp.data['puntoVenta'];
            tipoComprobanteLegal = resp.data['tipoComprobante'];
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'No se pudo obtener el CAE (${resp.data['error'] ?? 'error desconocido'}). El cobro se registrará como comprobante no fiscal.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Error al solicitar CAE: $e. El cobro se registrará como comprobante no fiscal.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      final batch = _firestore.batch();

      // 🚨 Si la liquidación masiva ya corrió para este período, existe una
      // deuda 'Cuota Mensual'/'Pendiente' real en la cuenta corriente que
      // este cobro manual está saldando: hay que marcarla pagada y recién
      // ahí incrementar saldoCuentaCorriente. Si todavía no corrió (el caso
      // más común: se cobra por ADELANTADO, y la liquidación se encarga de
      // omitir este período gracias al campo 'periodo' de abajo), nunca se
      // generó una deuda que compensar, así que no corresponde tocar el
      // saldo — sólo dejar la constancia de pago.
      final cuotaPendienteSnap = await _firestore
          .collection('socios')
          .doc(widget.socioId)
          .collection('cuenta_corriente')
          .where('periodo', isEqualTo: periodo)
          .where('tipo', isEqualTo: 'Cuota Mensual')
          .where('estado', isEqualTo: 'Pendiente')
          .limit(1)
          .get();

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
        'facturadoArca': _emitirFacturaFiscal && caeFactura != null,
        'cae':
            caeFactura ?? (_emitirFacturaFiscal ? 'ERROR_CAE' : 'NO_FISCAL'),
        if (vencimientoCaeFactura != null) 'vencimientoCae': vencimientoCaeFactura,
        if (nroFacturaLegal != null) 'nroFacturaLegal': nroFacturaLegal,
        if (puntoVentaLegal != null) 'puntoVentaLegal': puntoVentaLegal,
        if (tipoComprobanteLegal != null) 'tipoComprobanteLegal': tipoComprobanteLegal,
      });

      if (cuotaPendienteSnap.docs.isNotEmpty) {
        batch.update(cuotaPendienteSnap.docs.first.reference, {
          'estado': 'Pagado',
          'facturadoArca': _emitirFacturaFiscal && caeFactura != null,
          'cae':
              caeFactura ?? (_emitirFacturaFiscal ? 'ERROR_CAE' : 'NO_FISCAL'),
        });
        batch.update(
          _firestore.collection('socios').doc(widget.socioId),
          {'saldoCuentaCorriente': FieldValue.increment(monto)},
        );
      }

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

      // 💳 Si se cobra por MP, el registro ya quedó asentado arriba (mismo
      // criterio que POS/canchas: no se hace esperar al socio para dejar
      // constancia), y acá se muestra el QR real como verificación en vivo.
      if (_medioPago == 'Mercado Pago' && mounted) {
        await mostrarSelectorCobroMercadoPago(
          context,
          ruta: 'socios/${widget.socioId}/cuenta_corriente/${ctaCteRef.id}',
          campoMonto: 'monto',
          campoMedioPago: 'medioPago',
          concepto: 'Cuota $periodo - ${widget.nombreSocio}',
        );
      }

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
                'Mercado Pago',
                'Transferencia',
                'Tarjeta',
              ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              // 🧾 Sugiere factura fiscal para medios electrónicos y
              // comprobante no fiscal (X) para efectivo, pero el operador
              // sigue pudiendo tildar/destildar el switch de abajo a mano.
              onChanged: (v) => setState(() {
                _medioPago = v!;
                _emitirFacturaFiscal = esMedioPagoElectronico(_medioPago);
              }),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Emitir Factura Fiscal (ARCA)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Text(
                _emitirFacturaFiscal
                    ? 'Se solicitará el CAE a ARCA al confirmar el cobro.'
                    : 'Se registra como comprobante interno, sin CAE.',
                style: const TextStyle(fontSize: 11),
              ),
              value: _emitirFacturaFiscal,
              onChanged: (v) => setState(() => _emitirFacturaFiscal = v),
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
