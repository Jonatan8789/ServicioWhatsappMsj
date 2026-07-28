import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:natatorio_app/features/socios/socio_model.dart';

class PlanPagoDialog extends StatefulWidget {
  final SocioModel socio;

  const PlanPagoDialog({super.key, required this.socio});

  @override
  State<PlanPagoDialog> createState() => _PlanPagoDialogState();
}

class _PlanPagoDialogState extends State<PlanPagoDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _cargando = true;
  bool _procesando = false;
  List<DocumentSnapshot> _movimientosPendientes = [];

  double _totalDeudaSeleccionada = 0.0;
  final Set<String> _idsSeleccionados = {};

  // Parámetros de Financiación
  final TextEditingController _anticipoCtrl = TextEditingController(text: '0');
  int _cantidadCuotas = 3;
  double _porcentajeInteres = 0.0;

  @override
  void initState() {
    super.initState();
    _cargarDeudaPendiente();
  }

  @override
  void dispose() {
    _anticipoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDeudaPendiente() async {
    try {
      final snap = await _firestore
          .collection('socios')
          .doc(widget.socio.id)
          .collection('cuenta_corriente')
          .where('estado', isEqualTo: 'Pendiente')
          .get();

      setState(() {
        _movimientosPendientes = snap.docs;
        for (var doc in _movimientosPendientes) {
          _idsSeleccionados.add(doc.id);
        }
        _recalcularTotal();
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  void _recalcularTotal() {
    double suma = 0.0;
    for (var doc in _movimientosPendientes) {
      if (_idsSeleccionados.contains(doc.id)) {
        final data = doc.data() as Map<String, dynamic>;
        suma += (data['monto'] as num).toDouble();
      }
    }
    setState(() => _totalDeudaSeleccionada = suma);
  }

  double get _montoAFinanciar {
    final anticipo = double.tryParse(_anticipoCtrl.text.trim()) ?? 0.0;
    final saldo = _totalDeudaSeleccionada - anticipo;
    return saldo < 0 ? 0.0 : saldo;
  }

  double get _totalConInteres {
    return _montoAFinanciar * (1 + (_porcentajeInteres / 100));
  }

  double get _valorCuotaMensual {
    if (_cantidadCuotas <= 0) return 0.0;
    return _totalConInteres / _cantidadCuotas;
  }

  Future<void> _confirmarPlanPago() async {
    if (_idsSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una cuota en mora.')),
      );
      return;
    }

    setState(() => _procesando = true);

    try {
      final WriteBatch batch = _firestore.batch();
      final double anticipo = double.tryParse(_anticipoCtrl.text.trim()) ?? 0.0;
      final String idPlan = "PLAN_${DateTime.now().millisecondsSinceEpoch}";

      // 1. Marcar las cuotas originales seleccionadas como 'Refinanciada'
      for (var docId in _idsSeleccionados) {
        final ref = _firestore
            .collection('socios')
            .doc(widget.socio.id)
            .collection('cuenta_corriente')
            .doc(docId);
        batch.update(ref, {
          'estado': 'Refinanciada',
          'idPlanPago': idPlan,
        });
      }

      // Recomponer saldo cancelando la deuda vieja seleccionada
      double ajusteSaldoSocio = _totalDeudaSeleccionada;

      // 2. Registramos el anticipo si hubo
      if (anticipo > 0) {
        final refAnticipo = _firestore
            .collection('socios')
            .doc(widget.socio.id)
            .collection('cuenta_corriente')
            .doc();

        batch.set(refAnticipo, {
          'fecha': DateTime.now(),
          'tipo': 'Anticipo Plan Pago',
          'concepto': 'Anticipo inicial - Plan de Pago #$idPlan',
          'monto': anticipo,
          'estado': 'Pagado',
          'idPlanPago': idPlan,
        });

        ajusteSaldoSocio -= anticipo; // Se achica la deuda por lo entregado
      }

      // 3. Generar los compromisos de cuotas refinanciadas
      final DateTime hoy = DateTime.now();
      for (int i = 1; i <= _cantidadCuotas; i++) {
        final DateTime fechaVencimiento = DateTime(hoy.year, hoy.month + i, 10);
        final refCuotaPlan = _firestore
            .collection('socios')
            .doc(widget.socio.id)
            .collection('cuenta_corriente')
            .doc();

        batch.set(refCuotaPlan, {
          'fecha': DateTime.now(),
          'fechaVencimiento': fechaVencimiento,
          'tipo': 'Cuota Plan Pago',
          'concepto': 'Plan #$idPlan - Cuota $i/$_cantidadCuotas (Venc: ${fechaVencimiento.day}/${fechaVencimiento.month}/${fechaVencimiento.year})',
          'monto': _valorCuotaMensual,
          'estado': 'Pendiente',
          'idPlanPago': idPlan,
        });
      }

      // Aumentamos la deuda con las cuotas nuevas (que ya incluyen el interés)
      ajusteSaldoSocio -= _totalConInteres;

      // 4. Actualizar saldo final en el socio
      final refSocio = _firestore.collection('socios').doc(widget.socio.id);
      batch.update(refSocio, {
        'saldoCuentaCorriente': FieldValue.increment(ajusteSaldoSocio),
      });

      await batch.commit();

      // 📲 Notificación opcional por WhatsApp
      if (widget.socio.telefono.isNotEmpty) {
        _enviarWhatsAppPlan(
          telefono: widget.socio.telefono,
          nombre: widget.socio.nombre,
          cuotas: _cantidadCuotas,
          montoCuota: _valorCuotaMensual,
          anticipo: anticipo,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🤝 ¡Plan de pago generado correctamente!'),
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

  Future<void> _enviarWhatsAppPlan({
    required String telefono,
    required String nombre,
    required int cuotas,
    required double montoCuota,
    required double anticipo,
  }) async {
    final mensaje = '''
🤝 *ACUERDO DE REFINANCIACIÓN - CLUB AQUA & PADDLE*

Hola *$nombre*, confirmamos la refinanciación de tu cuenta:

${anticipo > 0 ? '💰 *Anticipo Recibido:* \$${anticipo.toStringAsFixed(0)} ARS\n' : ''}📅 *Plan:* $cuotas cuotas mensuales de \$${montoCuota.toStringAsFixed(2)} ARS.

Agradecemos tu compromiso para mantener tu cuenta al día.
''';

    try {
      await http.post(
        Uri.parse('http://localhost:3000/send-whatsapp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': telefono, 'message': mensaje}),
      );
    } catch (e) {
      print('Error al enviar WhatsApp: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        padding: const EdgeInsets.all(24),
        child: _cargando
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Refinanciar Deuda: ${widget.socio.nombre}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LISTA DE DEUDAS A SELECCIONAR
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '1. Cuotas Vencidas en Mora:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 220,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _movimientosPendientes.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'El socio no posee cuotas pendientes.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _movimientosPendientes.length,
                                      itemBuilder: (context, idx) {
                                        final doc = _movimientosPendientes[idx];
                                        final data = doc.data() as Map<String, dynamic>;
                                        final bool sel = _idsSeleccionados.contains(doc.id);

                                        return CheckboxListTile(
                                          dense: true,
                                          title: Text(
                                            data['concepto'] ?? 'Cuota Pendiente',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          subtitle: Text(
                                            'Monto: \$${(data['monto'] as num).toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red,
                                            ),
                                          ),
                                          value: sel,
                                          onChanged: (val) {
                                            setState(() {
                                              if (val == true) {
                                                _idsSeleccionados.add(doc.id);
                                              } else {
                                                _idsSeleccionados.remove(doc.id);
                                              }
                                              _recalcularTotal();
                                            });
                                          },
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),

                      // CALCULADORA DE PLAN
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '2. Estructura del Convenio:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Deuda Seleccionada: \$${_totalDeudaSeleccionada.toStringAsFixed(0)} ARS',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _anticipoCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Entrega Inicial / Anticipo (\$)Text',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _cantidadCuotas,
                                    decoration: const InputDecoration(
                                      labelText: 'N° Cuotas',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: [2, 3, 4, 6, 9, 12]
                                        .map((c) => DropdownMenuItem(
                                              value: c,
                                              child: Text('$c cuotas'),
                                            ))
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => _cantidadCuotas = v!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<double>(
                                    value: _porcentajeInteres,
                                    decoration: const InputDecoration(
                                      labelText: 'Interés Total',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: [0.0, 5.0, 10.0, 15.0, 20.0]
                                        .map((i) => DropdownMenuItem(
                                              value: i,
                                              child: Text('${i.toStringAsFixed(0)}%'),
                                            ))
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => _porcentajeInteres = v!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.teal.shade200),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Financiado Total:'),
                                      Text(
                                        '\$${_totalConInteres.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'CUOTA MENSUAL:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '\$${_valorCuotaMensual.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      _procesando
                          ? const CircularProgressIndicator()
                          : ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                              ),
                              onPressed: _confirmarPlanPago,
                              icon: const Icon(Icons.handshake_rounded,
                                  color: Colors.white),
                              label: const Text(
                                'Aprobar Plan de Pago',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}