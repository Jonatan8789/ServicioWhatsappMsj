import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cloud_functions;
import 'package:http/http.dart' as http;
import 'producto_buffet_model.dart';

class FirebaseFunctions {
  static _FirebaseFunctionsWrapper get instance => _FirebaseFunctionsWrapper();
}

class _FirebaseFunctionsWrapper {
  cloud_functions.HttpsCallable httpsCallable(String functionName) {
    return cloud_functions.FirebaseFunctions.instance.httpsCallable(
      functionName,
    );
  }
}

class PosCajaPage extends StatefulWidget {
  const PosCajaPage({super.key});

  @override
  State<PosCajaPage> createState() => _PosCajaPageState();
}

class _PosCajaPageState extends State<PosCajaPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _carrito = [];
  final TextEditingController _escanerCtrl = TextEditingController();
  final FocusNode _escanerFocus = FocusNode();

  String? _socioSeleccionadoId;
  String? _idVentaPendienteActual;
  String _busquedaSocioPOS = "";
  Map<String, dynamic>? _socioSeleccionadoPOS;

  List<DocumentSnapshot> _reservasPendientesDelSocio = [];
  bool _buscandoReservas = false;

  String? _mesaSeleccionadaNombre;
  final String _usuarioOperador = "Administrador Central";

  @override
  void dispose() {
    _escanerCtrl.dispose();
    _escanerFocus.dispose();
    super.dispose();
  }

  double get totalCarrito {
    return _carrito.fold(
      0,
      (sum, item) => sum + (item['precio'] * item['cantidad']),
    );
  }

  Future<void> _seleccionarMesa(
    String nombreMesa,
    Map<String, dynamic>? mesaData,
  ) async {
    setState(() {
      _mesaSeleccionadaNombre = nombreMesa;
      _carrito = [];
      if (mesaData != null && mesaData['items'] != null) {
        final List<dynamic> itemsMesa = mesaData['items'];
        for (var it in itemsMesa) {
          _carrito.add(Map<String, dynamic>.from(it));
        }
        _socioSeleccionadoId = mesaData['socioId'];
        _socioSeleccionadoPOS = mesaData['socioData'];
      } else {
        _socioSeleccionadoId = null;
        _socioSeleccionadoPOS = null;
      }
    });
    if (_socioSeleccionadoId != null) {
      _buscarReservasPendientes(_socioSeleccionadoId!);
    }
  }

  Future<void> _guardarCambiosEnMesa() async {
    if (_mesaSeleccionadaNombre == null) return;
    try {
      if (_carrito.isEmpty) {
        await _firestore
            .collection('mesas_activas')
            .doc(_mesaSeleccionadaNombre!)
            .delete();
      } else {
        await _firestore
            .collection('mesas_activas')
            .doc(_mesaSeleccionadaNombre!)
            .set({
              'items': _carrito,
              'total': totalCarrito,
              'socioId': _socioSeleccionadoId,
              'socioData': _socioSeleccionadoPOS,
              'ultimaActualizacion': DateTime.now(),
            });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📊 Cuenta de $_mesaSeleccionadaNombre resguardada.'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    } catch (e) {
      print("Error guardando mesa: $e");
    }
  }

  Future<void> _despacharComandaCocina() async {
    final itemsParaCocinar = _carrito
        .where((i) => i['requiereCocina'] == true)
        .toList();
    if (itemsParaCocinar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ No hay minutas ni platos elaborados en este pedido.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await _firestore.collection('comandas_cocina').add({
        'mesa': _mesaSeleccionadaNombre ?? 'Mostrador / Barra',
        'fecha': DateTime.now(),
        'estado': 'Pendiente',
        'detalles': itemsParaCocinar
            .map((i) => {'nombre': i['nombre'], 'cantidad': i['cantidad']})
            .toList(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🍳 ¡Comanda enviada a la pantalla de la Cocina!'),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      print("Error sending comanda: $e");
    }
  }

  Future<void> _buscarReservasPendientes(String socioId) async {
    setState(() {
      _buscandoReservas = true;
      _reservasPendientesDelSocio = [];
    });
    try {
      final snapshot = await _firestore
          .collection('ventas_pendientes')
          .where('socio_id', isEqualTo: socioId)
          .where('estado', isEqualTo: 'Pendiente')
          .get();
      setState(() {
        _reservasPendientesDelSocio = snapshot.docs;
        _buscandoReservas = false;
      });
    } catch (e) {
      setState(() => _buscandoReservas = false);
    }
  }

  void _cargarReservaAlCarrito(DocumentSnapshot docVenta) {
    final data = docVenta.data() as Map<String, dynamic>;
    final List<dynamic> itemsReserva = data['items'] ?? [];
    setState(() {
      _idVentaPendienteActual = docVenta.id;
      for (var item in itemsReserva) {
        _carrito.add({
          'id': item['id'] ?? 'cancha_paddle_unificada',
          'nombre': item['nombre'] ?? 'Reserva de Cancha',
          'precio': (item['precio'] as num).toDouble(),
          'cantidad': item['cantidad'] ?? 1,
          'es_producto_fisico': item['es_producto_fisico'] ?? false,
          'requiereCocina': false,
          'origen_pendiente_id': docVenta.id,
        });
      }
    });
  }

  /// 📲 Enviar comprobante/recibo de pago por WhatsApp
  Future<void> _enviarReciboPagoWhatsApp({
    required String telefono,
    required String nombreSocio,
    required double total,
    required String medioPago,
    required String tipoComprobante,
    String? cae,
  }) async {
    final telefonoLimpio = telefono.replaceAll(RegExp(r'\D'), '');
    if (telefonoLimpio.isEmpty) return;

    final String fechaStr =
        "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";

    final mensaje =
        '''
🧾 *COMPROBANTE DE PAGO - OQUA CLUB DEPORTIVO*

Hola *$nombreSocio*, registramos tu pago correctamente:

📅 *Fecha:* $fechaStr
💰 *Monto Total:* \$${total.toStringAsFixed(2)} ARS
💳 *Forma de Pago:* $medioPago
📄 *Comprobante:* $tipoComprobante${cae != null && cae != 'NO_FISCAL_X' ? '\n🔍 *CAE:* $cae' : ''}

¡Muchas gracias!
''';

    try {
      await http.post(
        Uri.parse('http://localhost:3000/send-whatsapp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': telefonoLimpio, 'message': mensaje}),
      );
    } catch (e) {
      print('⚠️ No se pudo enviar el recibo de pago por WhatsApp: $e');
    }
  }

  void _procesarCobroMercadoPagoModal(double montoTotal, String ventaId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _firestore
              .collection('ventas_buffet')
              .doc(ventaId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>?;

              if (data != null && data['estadoPagoMP'] == 'Aprobado') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('✅ ¡Pago Aprobado por Mercado Pago!'),
                    ),
                  );
                });
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              title: const Row(
                children: [
                  Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.lightBlueAccent,
                    size: 28,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Cobro Mercado Pago',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Monto: \$${montoTotal.toStringAsFixed(2)} ARS',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 100,
                          color: Color(0xFF009EE3),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Esperando confirmación de pago...',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(color: Colors.lightBlueAccent),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    FirebaseFunctions.instance
        .httpsCallable('crearCobroMercadoPago')
        .call({
          'monto': montoTotal,
          'concepto': 'Cobro POS Club Aqua & Paddle',
          'ventaId': ventaId,
        })
        .catchError((dynamic e) {
          print("Error iniciando cobro MP: $e");
        });
  }

  void _mostrarDialogoCobro() {
    if (_carrito.isEmpty) return;

    String medioPagoSeleccionado = 'Efectivo ARS';
    bool emitirFacturaFiscal = true;

    final listaMedios = [
      'Efectivo ARS',
      'Efectivo USD',
      'Mercado Pago',
      'MODO',
      'Tarjeta Débito',
      'Tarjeta Crédito',
      'Transferencia Bancaria',
      'Cuenta Corriente',
    ];
    final recibidoCtrl = TextEditingController();
    final cuponCtrl = TextEditingController();
    final autCtrl = TextEditingController();
    final operacionCtrl = TextEditingController();
    String cuotasSeleccionadas = '1 Cuota (S/Interés)';
    double vueltoCalculado = 0.0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Procesar Cobro Detallado'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total a Pagar: \$${totalCarrito.toStringAsFixed(2)} ARS',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: emitirFacturaFiscal
                          ? Colors.indigo.shade50
                          : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: emitirFacturaFiscal
                            ? Colors.indigo.shade200
                            : Colors.amber.shade300,
                      ),
                    ),
                    child: SwitchListTile(
                      title: Text(
                        emitirFacturaFiscal
                            ? 'Emitir Factura ARCA (Oficial)'
                            : 'Comprobante X (No Fiscal / Gastos Menores)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: emitirFacturaFiscal
                              ? Colors.indigo.shade900
                              : Colors.amber.shade900,
                        ),
                      ),
                      subtitle: Text(
                        emitirFacturaFiscal
                            ? 'Emitirá comprobante electrónico con CAE'
                            : 'Registra en caja e inventario sin enviar a ARCA',
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: emitirFacturaFiscal,
                      activeThumbColor: Colors.indigo,
                      onChanged: (val) =>
                          setModalState(() => emitirFacturaFiscal = val),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: medioPagoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Canal de Cobro',
                      border: OutlineInputBorder(),
                    ),
                    items: listaMedios
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) =>
                        setModalState(() => medioPagoSeleccionado = val!),
                  ),
                  const SizedBox(height: 16),
                  if (medioPagoSeleccionado.contains('Efectivo')) ...[
                    TextField(
                      controller: recibidoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monto Recibido',
                        border: OutlineInputBorder(),
                        prefixText: '\$ ',
                      ),
                      onChanged: (v) {
                        final recibido = double.tryParse(v) ?? 0.0;
                        setModalState(
                          () => vueltoCalculado = recibido - totalCarrito,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: vueltoCalculado >= 0
                          ? Colors.blue.shade50
                          : Colors.red.shade50,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Vuelto:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '\$${vueltoCalculado >= 0 ? vueltoCalculado.toStringAsFixed(2) : '0.00'}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: vueltoCalculado >= 0
                                  ? Colors.blue.shade800
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (medioPagoSeleccionado == 'Tarjeta Débito' ||
                      medioPagoSeleccionado == 'Tarjeta Crédito') ...[
                    TextField(
                      controller: cuponCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Número de Cupón Posnet',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: autCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Código de Autorización',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (medioPagoSeleccionado == 'Tarjeta Crédito') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: cuotasSeleccionadas,
                      decoration: const InputDecoration(
                        labelText: 'Plan de Financiación',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          [
                                '1 Cuota (S/Interés)',
                                '3 Cuotas (Ahora 3)',
                                '6 Cuotas (Plan Local)',
                              ]
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                      onChanged: (v) => cuotasSeleccionadas = v!,
                    ),
                  ],
                  if (medioPagoSeleccionado == 'Transferencia Bancaria' ||
                      medioPagoSeleccionado == 'Mercado Pago' ||
                      medioPagoSeleccionado == 'MODO') ...[
                    TextField(
                      controller: operacionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Número de Operación / Referencia',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
              ),
              onPressed: () async {
                if (medioPagoSeleccionado.contains('Efectivo')) {
                  final rec = double.tryParse(recibidoCtrl.text) ?? 0.0;
                  if (rec < totalCarrito) return;
                }
                Map<String, dynamic> metadata = {
                  'cupon': cuponCtrl.text.trim(),
                  'codigo_autorizacion': autCtrl.text.trim(),
                  'nro_operacion': operacionCtrl.text.trim(),
                  'cuotas_plan': medioPagoSeleccionado == 'Tarjeta Crédito'
                      ? cuotasSeleccionadas
                      : '1',
                };

                Navigator.pop(context);
                final String? ventaIdProcesada = await _procesarVentaFirestore(
                  medio: medioPagoSeleccionado,
                  metadata: metadata,
                  emitirFiscal: emitirFacturaFiscal,
                );

                if (medioPagoSeleccionado == 'Mercado Pago' &&
                    ventaIdProcesada != null) {
                  _procesarCobroMercadoPagoModal(
                    totalCarrito,
                    ventaIdProcesada,
                  );
                }
              },
              child: Text(
                emitirFacturaFiscal
                    ? 'Confirmar y Fiscalizar'
                    : 'Emitir Ticket X (No Fiscal)',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _procesarVentaFirestore({
    required String medio,
    required Map<String, dynamic> metadata,
    required bool emitirFiscal,
  }) async {
    try {
      final cajaQuery = await _firestore
          .collection('control_cajas')
          .where('usuario', isEqualTo: _usuarioOperador)
          .where('estado', isEqualTo: 'Abierta')
          .limit(1)
          .get();

      if (cajaQuery.docs.isEmpty) {
        _notificarAlertaCaja(
          '⚠️ Terminal Bloqueada: No hay una apertura de caja activa para tu usuario.',
        );
        return null;
      }
      final docCajaId = cajaQuery.docs.first.id;

      WriteBatch batch = _firestore.batch();

      for (var item in _carrito) {
        if (item['esCombo'] == true && item['componentes'] != null) {
          final List<dynamic> componentesCombo = item['componentes'];
          final int cantidadComboComprada = item['cantidad'] ?? 1;

          for (var comp in componentesCombo) {
            final String subProdId = comp['productoId'];
            final int subCantUnidad = comp['cantidad'] ?? 1;
            final int totalBajaStock = subCantUnidad * cantidadComboComprada;

            DocumentReference subProdRef = _firestore
                .collection('inventario_general')
                .doc(subProdId);
            batch.update(subProdRef, {
              'stockActual': FieldValue.increment(-totalBajaStock),
            });
          }
        } else if (item['es_producto_fisico'] == true) {
          DocumentReference prodRef = _firestore
              .collection('inventario_general')
              .doc(item['id']);
          batch.update(prodRef, {
            'stockActual': FieldValue.increment(-(item['cantidad'] ?? 1)),
          });
        }
      }

      DocumentReference nuevaVentaRef = _firestore
          .collection('ventas_buffet')
          .doc();

      String? dniSocioEnvio = _socioSeleccionadoPOS != null
          ? _socioSeleccionadoPOS!['dni']?.toString()
          : null;

      batch.set(nuevaVentaRef, {
        'items': _carrito,
        'total': totalCarrito,
        'medio_pago': medio,
        'fecha': DateTime.now(),
        'usuario': _usuarioOperador,
        'socio_id': _socioSeleccionadoId,
        'metadata_comprobante': metadata,
        'origen_salón': _mesaSeleccionadaNombre ?? 'Mostrador Directo',
        'tipoComprobante': emitirFiscal
            ? 'Factura Fiscal ARCA'
            : 'Comprobante X (No Fiscal)',
        'fiscalizado': !emitirFiscal,
        'cae': emitirFiscal ? null : 'NO_FISCAL_X',
        'estadoPagoMP': medio == 'Mercado Pago' ? 'Pendiente' : 'Aprobado',
      });

      if (medio == 'Cuenta Corriente' && _socioSeleccionadoId != null) {
        DocumentReference ctaCteRef = _firestore
            .collection('socios')
            .doc(_socioSeleccionadoId!)
            .collection('cuenta_corriente')
            .doc();
        batch.set(ctaCteRef, {
          'fecha': DateTime.now(),
          'tipo': 'Consumo Buffet (Deuda)',
          'monto': totalCarrito,
          'detalle': 'Consumo diferido a Cuenta Corriente',
        });
      }

      String campoIncrementar = 'totalEfectivoARS';
      if (medio == 'Efectivo USD') campoIncrementar = 'totalEfectivoUSD';
      if (medio == 'Mercado Pago') campoIncrementar = 'totalMercadoPago';
      if (medio == 'MODO') campoIncrementar = 'totalModo';
      if (medio == 'Tarjeta Débito') campoIncrementar = 'totalTarjetaDebito';
      if (medio == 'Tarjeta Crédito') campoIncrementar = 'totalTarjetaCredito';
      if (medio == 'Transferencia Bancaria')
        campoIncrementar = 'totalTransferencia';
      if (medio == 'Cuenta Corriente') campoIncrementar = 'totalCtaCte';

      batch.update(_firestore.collection('control_cajas').doc(docCajaId), {
        campoIncrementar: FieldValue.increment(totalCarrito),
      });

      if (_mesaSeleccionadaNombre != null) {
        batch.delete(
          _firestore.collection('mesas_activas').doc(_mesaSeleccionadaNombre!),
        );
      }

      if (_idVentaPendienteActual != null) {
        batch.update(
          _firestore
              .collection('ventas_pendientes')
              .doc(_idVentaPendienteActual!),
          {'estado': 'Cobrado', 'fecha_pago': DateTime.now()},
        );
      }

      final String idVentaAsignada = nuevaVentaRef.id;
      final double totalParaFiscalizar = totalCarrito;

      await batch.commit();

      // 📲 DISPARO AUTOMÁTICO DE RECIBO POR WHATSAPP AL SOCIO
      final String? telefonoSocio = _socioSeleccionadoPOS != null
          ? _socioSeleccionadoPOS!['telefono']
          : null;
      final String nombreSocio = _socioSeleccionadoPOS != null
          ? '${_socioSeleccionadoPOS!['nombre'] ?? ''} ${_socioSeleccionadoPOS!['apellido'] ?? ''}'
                .trim()
          : 'Cliente';

      if (telefonoSocio != null && telefonoSocio.isNotEmpty) {
        _enviarReciboPagoWhatsApp(
          telefono: telefonoSocio,
          nombreSocio: nombreSocio,
          total: totalParaFiscalizar,
          medioPago: medio,
          tipoComprobante: emitirFiscal
              ? 'Factura Fiscal ARCA'
              : 'Comprobante X',
          cae: emitirFiscal ? null : 'NO_FISCAL_X',
        );
      }

      setState(() {
        _carrito.clear();
        _socioSeleccionadoId = null;
        _socioSeleccionadoPOS = null;
        _idVentaPendienteActual = null;
        _busquedaSocioPOS = "";
        _reservasPendientesDelSocio = [];
        _mesaSeleccionadaNombre = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            emitirFiscal
                ? '✅ Cobro registrado. Solicitando CAE a ARCA...'
                : '✅ Ticket X generado (Registrado en caja e inventario)',
          ),
          backgroundColor: emitirFiscal ? Colors.green : Colors.amber.shade900,
        ),
      );

      if (emitirFiscal) {
        _ejecutarFiscalizacionEnNube(
          idTicket: idVentaAsignada,
          total: totalParaFiscalizar,
          dniSocio: dniSocioEnvio,
        );
      }

      return idVentaAsignada;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<void> _ejecutarFiscalizacionEnNube({
    required String idTicket,
    required double total,
    String? dniSocio,
  }) async {
    try {
      final configDoc = await _firestore
          .collection('configuraciones_fiscales')
          .doc('arca_reglas')
          .get();

      if (!configDoc.exists) {
        throw Exception(
          "No se encontró la configuración fiscal en 'configuraciones_fiscales/arca_reglas'.",
        );
      }

      final configData = configDoc.data()!;
      final int cuit = configData['cuit'] ?? 0;
      final int puntoVenta = configData['puntoVenta'] ?? 1;
      final int comprobanteTipo = configData['comprobanteTipo'] ?? 11;
      final bool modoProduccion = configData['modoProduccion'] ?? false;

      var callable = FirebaseFunctions.instance.httpsCallable(
        'emitirFacturaArca',
      );

      final response = await callable.call(<String, dynamic>{
        'total': total,
        'socioDni': (dniSocio != null && dniSocio.trim().isNotEmpty)
            ? dniSocio.trim()
            : null,
        'cuit': cuit,
        'puntoVenta': puntoVenta,
        'comprobanteTipo': comprobanteTipo,
        'modoProduccion': modoProduccion,
      });

      final resultado = response.data;

      if (resultado['success'] == true) {
        await _firestore.collection('ventas_buffet').doc(idTicket).update({
          'fiscalizado': true,
          'cae': resultado['cae'],
          'vencimientoCae': resultado['vencimientoCae'],
          'nroFacturaLegal': resultado['nroFactura'],
          'puntoVentaLegal': resultado['puntoVenta'] ?? puntoVenta,
          'tipoComprobanteLegal':
              resultado['tipoComprobante'] ?? comprobanteTipo,
          'fechaFiscalizacion': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.indigo.shade800,
              duration: const Duration(seconds: 5),
              content: Row(
                children: [
                  const Icon(Icons.verified, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🧾 Comprobante ARCA Emitido: PV ${puntoVenta.toString().padLeft(4, '0')}-${resultado['nroFactura'].toString().padLeft(8, '0')} (CAE: ${resultado['cae']})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        await _firestore.collection('ventas_buffet').doc(idTicket).update({
          'fiscalizado': false,
          'errorFiscalMsg':
              resultado['error'] ?? 'Error desconocido al fiscalizar',
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade900,
              content: Text('⚠️ Falló ARCA: ${resultado['error']}'),
            ),
          );
        }
      }
    } catch (e) {
      print("Error fiscalizando con ARCA: $e");
      await _firestore.collection('ventas_buffet').doc(idTicket).update({
        'fiscalizado': false,
        'errorFiscalMsg': e.toString(),
      });
    }
  }

  void _notificarAlertaCaja(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _abrirMenuFlotanteCajaPropia() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('control_cajas')
              .where('usuario', isEqualTo: _usuarioOperador)
              .where('estado', isEqualTo: 'Abierta')
              .limit(1)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs;

            if (docs.isEmpty) {
              final arsCtrl = TextEditingController();
              final usdCtrl = TextEditingController();
              String terminalSel = 'Caja Buffet 1';

              return Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 32,
                  right: 32,
                  top: 24,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Apertura de Turno Operativo',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Declará los montos iniciales de tu cajón comercial para habilitar las ventas.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: terminalSel,
                      decoration: const InputDecoration(
                        labelText: 'Terminal Asignada',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Caja Buffet 1',
                          child: Text('Caja Buffet 1'),
                        ),
                        DropdownMenuItem(
                          value: 'Barra Principal',
                          child: Text('Barra Principal'),
                        ),
                      ],
                      onChanged: (v) => terminalSel = v!,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: arsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Fondo Inicial Pesos (\$ ARS)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Fondo Inicial Dólares (US\$ USD)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: () async {
                        final ars = double.tryParse(arsCtrl.text.trim()) ?? 0.0;
                        final usd = double.tryParse(usdCtrl.text.trim()) ?? 0.0;

                        await _firestore.collection('control_cajas').add({
                          'usuario': _usuarioOperador,
                          'nombreCajaTerminal': terminalSel,
                          'fechaApertura': DateTime.now(),
                          'saldoInicialARS': ars,
                          'saldoInicialUSD': usd,
                          'totalEfectivoARS': 0.0,
                          'totalEfectivoUSD': 0.0,
                          'totalMercadoPago': 0.0,
                          'totalModo': 0.0,
                          'totalTarjetaDebito': 0.0,
                          'totalTarjetaCredito': 0.0,
                          'totalTransferencia': 0.0,
                          'totalCtaCte': 0.0,
                          'estado': 'Abierta',
                        });
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Confirmar Apertura e Iniciar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              );
            }

            final docCaja = docs.first;
            final dataCaja = docCaja.data() as Map<String, dynamic>;
            final double esperadoArs =
                (dataCaja['saldoInicialARS'] ?? 0.0) +
                (dataCaja['totalEfectivoARS'] ?? 0.0);

            final montoMovCtrl = TextEditingController();
            final motivoMovCtrl = TextEditingController();
            final realArsCtrl = TextEditingController();
            String operacionMov = 'Ingreso Directo';

            return StatefulBuilder(
              builder: (context, setModalState) => Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 32,
                  right: 32,
                  top: 24,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Mi Caja: [${dataCaja['nombreCajaTerminal']}]',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ACTIVA',
                              style: TextStyle(
                                color: Colors.green.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Teórico en Caja: \$${esperadoArs.toStringAsFixed(2)} ARS',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const Divider(height: 24),

                      const Text(
                        'Asentar Novedad Financiera Directa:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: operacionMov,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Ingreso Directo',
                            child: Text('Ingreso Directo (Inyección Fondo)'),
                          ),
                          DropdownMenuItem(
                            value: 'Egreso Directo',
                            child: Text('Egreso Directo (Pago Proveedor)'),
                          ),
                          DropdownMenuItem(
                            value: 'Egreso para Banco (Depósito)',
                            child: Text('Retiro para Depósito Bancario'),
                          ),
                          DropdownMenuItem(
                            value: 'Fallo de Caja (Faltante)',
                            child: Text('Declarar Faltante Breve'),
                          ),
                        ],
                        onChanged: (v) => operacionMov = v!,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: montoMovCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Monto (\$)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: motivoMovCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Concepto / Justificación',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          minimumSize: const Size.fromHeight(40),
                        ),
                        onPressed: () async {
                          final m =
                              double.tryParse(montoMovCtrl.text.trim()) ?? 0.0;
                          final mot = motivoMovCtrl.text.trim();
                          if (m <= 0 || mot.isEmpty) return;

                          double factor =
                              (operacionMov.contains('Egreso') ||
                                  operacionMov.contains('Faltante'))
                              ? -1.0
                              : 1.0;
                          await _firestore
                              .collection('control_cajas')
                              .doc(docCaja.id)
                              .update({
                                'totalEfectivoARS': FieldValue.increment(
                                  m * factor,
                                ),
                              });
                          await _firestore
                              .collection('auditoria_movimientos_caja')
                              .add({
                                'fecha': DateTime.now(),
                                'cajaId': docCaja.id,
                                'tipo': operacionMov,
                                'monto': m,
                                'justificacion': mot,
                                'ejecuto': 'Operario POS',
                              });
                          montoMovCtrl.clear();
                          motivoMovCtrl.clear();
                          Navigator.pop(context);
                        },
                        icon: const Icon(
                          Icons.playlist_add_check_rounded,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Asentar Movimiento',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),

                      const Divider(height: 32),

                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text(
                                'Constancia de Control Parcial',
                              ),
                              content: Text(
                                'Efectivo acumulado a entregar a Administración:\n\n\$${esperadoArs.toStringAsFixed(2)} ARS.\n\nSe emitirá la orden de resguardo sin cerrar la terminal.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cerrar'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.assignment_turned_in_rounded,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Reporte de Entrega Parcial de Activos',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),

                      const Divider(height: 32),

                      const Text(
                        'Cierre de Turno Definitivo:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: realArsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Efectivo Real Físico en Caja (\$ ARS)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () async {
                          final realArs =
                              double.tryParse(realArsCtrl.text.trim()) ?? -1.0;
                          if (realArs < 0) return;

                          final dif = realArs - esperadoArs;

                          await _firestore
                              .collection('control_cajas')
                              .doc(docCaja.id)
                              .update({
                                'state': 'Cerrada',
                                'estado': 'Cerrada',
                                'fechaCierre': DateTime.now(),
                                'cierreRealEfectivoARS': realArs,
                                'cierreRealEfectivoUSD':
                                    dataCaja['totalEfectivoUSD'] ?? 0.0,
                              });

                          if (dif != 0) {
                            await _firestore
                                .collection('auditoria_movimientos_caja')
                                .add({
                                  'fecha': DateTime.now(),
                                  'cajaId': docCaja.id,
                                  'tipo': dif < 0
                                      ? 'Fallo Automático (Faltante)'
                                      : 'Fallo Automático (Sobrante)',
                                  'monto': dif.abs(),
                                  'justificacion':
                                      'Descalce detectado por el operario al cerrar turno desde el POS.',
                                  'ejecuto': 'Sistema POS',
                                });
                          }

                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Efectuar Arqueo y Cerrar Caja',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMapaMesasSalon() {
    final listadoMesasFijas = [
      'Mesa 1',
      'Mesa 2',
      'Mesa 3',
      'Mesa 4',
      'Barra 1',
      'Barra 2',
      'Cancha 1 Buffet',
      'VIP Terraza',
    ];

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('mesas_activas').snapshots(),
      builder: (context, snapshot) {
        Map<String, Map<String, dynamic>> mesasAbiertasMap = {};
        if (snapshot.hasData) {
          for (var d in snapshot.data!.docs) {
            mesasAbiertasMap[d.id] = d.data() as Map<String, dynamic>;
          }
        }

        return SizedBox(
          height: 75,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: listadoMesasFijas.length,
            itemBuilder: (context, idx) {
              final mNombre = listadoMesasFijas[idx];
              final estaAbierta = mesasAbiertasMap.containsKey(mNombre);
              final esLaSeleccionada = _mesaSeleccionadaNombre == mNombre;
              final double totalMesa = estaAbierta
                  ? (mesasAbiertasMap[mNombre]!['total'] as num).toDouble()
                  : 0.0;

              return InkWell(
                onTap: () =>
                    _seleccionarMesa(mNombre, mesasAbiertasMap[mNombre]),
                child: Container(
                  width: 115,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: esLaSeleccionada
                        ? Colors.indigo.shade600
                        : (estaAbierta ? Colors.red.shade50 : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: esLaSeleccionada
                          ? Colors.indigo
                          : (estaAbierta
                                ? Colors.red.shade300
                                : Colors.grey.shade300),
                      width: esLaSeleccionada ? 2.5 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mNombre,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: esLaSeleccionada ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        estaAbierta
                            ? '\$${totalMesa.toStringAsFixed(0)}'
                            : 'Libre',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: estaAbierta
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: esLaSeleccionada
                              ? Colors.white70
                              : (estaAbierta
                                    ? Colors.red.shade800
                                    : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBuscadorSocios() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Vincular Cliente / Socio responsable a Cuenta...',
                prefixIcon: Icon(Icons.person_search_rounded),
              ),
              onChanged: (val) => setState(() => _busquedaSocioPOS = val),
            ),
            if (_busquedaSocioPOS.length >= 3) _buildListaResultadosSocios(),
            if (_socioSeleccionadoPOS != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Socio Vinculado: ${_socioSeleccionadoPOS!['nombre'] ?? ''} ${_socioSeleccionadoPOS!['apellido'] ?? ''} - DNI: ${_socioSeleccionadoPOS!['dni'] ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() {
                        _socioSeleccionadoPOS = null;
                        _socioSeleccionadoId = null;
                        _reservasPendientesDelSocio = [];
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildListaResultadosSocios() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('socios').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        final query = _busquedaSocioPOS.toLowerCase().trim();

        final docs = snapshot.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};

          final String n = (data['nombre'] ?? '').toString().toLowerCase();
          final String a = (data['apellido'] ?? '').toString().toLowerCase();
          final String dni = (data['dni'] ?? '').toString().toLowerCase();
          final String email = (data['email'] ?? '').toString().toLowerCase();

          final String nombreCompleto = '$n $a';

          return n.contains(query) ||
              a.contains(query) ||
              dni.contains(query) ||
              email.contains(query) ||
              nombreCompleto.contains(query);
        }).toList();

        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Text(
              'No se encontró ningún socio con esos datos.',
              style: TextStyle(
                color: Colors.red,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data() as Map<String, dynamic>;
              final String socioNombre =
                  '${data['nombre'] ?? ''} ${data['apellido'] ?? ''}';
              final String socioDni = data['dni'] != null
                  ? ' - DNI: ${data['dni']}'
                  : '';

              return ListTile(
                leading: const Icon(
                  Icons.person_outline_rounded,
                  color: Colors.indigo,
                ),
                title: Text(
                  socioNombre,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'ID: ${d.id}$socioDni',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.indigo,
                ),
                onTap: () {
                  setState(() {
                    _socioSeleccionadoId = d.id;
                    _socioSeleccionadoPOS = data;
                    _busquedaSocioPOS = "";
                  });
                  _buscarReservasPendientes(d.id);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCatalogoProductos() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('inventario_general')
          .where('tipoInventario', isEqualTo: 'Buffet')
          .where('disponible', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;

        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
          ),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final p = ProductoBuffetModel.fromFirestore(docs[i]);
            final bool esUnCombo = p.esCombo;

            return InkWell(
              onTap: () {
                setState(() {
                  _carrito.add({
                    'id': p.id,
                    'nombre': esUnCombo ? '${p.nombre} (🍔COMBO)' : p.nombre,
                    'precio': p.precio,
                    'cantidad': 1,
                    'es_producto_fisico': !esUnCombo,
                    'esCombo': esUnCombo,
                    'requiereCocina': p.requiereCocina,
                    'componentes': p.componentes.map((c) => c.toMap()).toList(),
                  });
                });
              },
              child: Card(
                color: esUnCombo ? Colors.orange.shade50 : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: esUnCombo
                        ? Colors.orange.shade300
                        : Colors.grey.shade200,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$${p.precio.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: esUnCombo
                              ? Colors.orange.shade900
                              : Colors.teal,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPanelCarrito() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mesaSeleccionadaNombre == null
                ? 'Resumen de Compra Directa'
                : 'Detalle de Cuenta: $_mesaSeleccionadaNombre',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _carrito.isEmpty
                ? const Center(
                    child: Text(
                      'Ticket Vacío',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _carrito.length,
                    itemBuilder: (context, i) {
                      final item = _carrito[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item['nombre']),
                        subtitle: Text(
                          '${item['cantidad']} x \$${item['precio'].toStringAsFixed(0)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _carrito.removeAt(i)),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),
          if (_mesaSeleccionadaNombre != null) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade600,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _carrito.isEmpty ? null : _guardarCambiosEnMesa,
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Guardar Mesa'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _carrito.isEmpty
                        ? null
                        : _despacharComandaCocina,
                    icon: const Icon(Icons.soup_kitchen, size: 16),
                    label: const Text('A Cocina'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL:',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                '\$${totalCarrito.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
              ),
              onPressed: _carrito.isEmpty ? null : _mostrarDialogoCobro,
              child: const Text(
                'COBRAR VENTA',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirMenuFlotanteCajaPropia,
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.point_of_sale_rounded, color: Colors.white),
        label: const Text(
          'Mi Caja (Apertura / Cierre)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _mesaSeleccionadaNombre == null
                            ? 'Terminal de Ventas POS'
                            : 'Comandas & Cuentas: $_mesaSeleccionadaNombre',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_mesaSeleccionadaNombre != null)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => setState(() {
                            _mesaSeleccionadaNombre = null;
                            _carrito.clear();
                          }),
                          icon: const Icon(Icons.arrow_back, size: 16),
                          label: const Text('Volver a Mostrador'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildMapaMesasSalon(),
                  const SizedBox(height: 16),
                  _buildBuscadorSocios(),
                  if (_buscandoReservas)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: LinearProgressIndicator(color: Colors.indigo),
                    ),
                  if (_reservasPendientesDelSocio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ..._reservasPendientesDelSocio.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final List items = data['items'] ?? [];
                      double totalReserva = items.fold(
                        0,
                        (sum, i) => sum + (i['precio'] ?? 0),
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['origen'] ?? 'Reserva Pendiente',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF9A3412),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Conceptos: ${items.map((i) => i['nombre']).join(" + ")}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '\$${totalReserva.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFC2410C),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade600,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => _cargarReservaAlCarrito(doc),
                                  icon: const Icon(
                                    Icons.add_shopping_cart,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Cargar al Ticket',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 16),
                  Expanded(child: _buildCatalogoProductos()),
                ],
              ),
            ),
          ),
          Container(width: 1, color: Colors.grey.shade300),
          Expanded(flex: 2, child: _buildPanelCarrito()),
        ],
      ),
    );
  }
}

void mostrarTicketFiscalDialog(
  BuildContext context,
  Map<String, dynamic> venta,
) {
  final bool esFiscal = venta['cae'] != null && venta['cae'] != 'NO_FISCAL_X';
  final int tipoComp = venta['tipoComprobanteLegal'] ?? 11;
  String tipoLetra = 'C';
  if (tipoComp == 1) tipoLetra = 'A';
  if (tipoComp == 6) tipoLetra = 'B';

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.receipt_long,
            color: esFiscal ? Colors.indigo : Colors.amber.shade900,
          ),
          const SizedBox(width: 8),
          Text(
            esFiscal ? 'Comprobante Fiscal ARCA' : 'Comprobante X (No Fiscal)',
          ),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  esFiscal ? 'FACTURA $tipoLetra' : 'TICKET X',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Divider(height: 24),
            Text(
              'N° Comprobante: ${esFiscal ? "${venta['puntoVentaLegal']?.toString().padLeft(4, '0') ?? '0001'}-${venta['nroFacturaLegal']?.toString().padLeft(8, '0') ?? '00000000'}" : "X-00000000"}',
            ),
            Text(
              'Fecha: ${venta['fecha'] != null ? (venta['fecha'] as Timestamp).toDate().toString().substring(0, 16) : ''}',
            ),
            if (venta['socio_id'] != null)
              Text('Cliente / ID: ${venta['socio_id']}'),
            const Divider(),
            Text(
              'Monto Total: \$${(venta['total'] as num).toStringAsFixed(2)} ARS',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: esFiscal ? Colors.grey.shade100 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: esFiscal
                      ? Colors.grey.shade300
                      : Colors.amber.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    esFiscal
                        ? 'CAE: ${venta['cae'] ?? 'N/A'}'
                        : 'DOCUMENTO NO FISCAL',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (esFiscal)
                    Text(
                      'Vencimiento CAE: ${venta['vencimientoCae'] ?? 'N/A'}',
                    ),
                  const SizedBox(height: 6),
                  Text(
                    esFiscal
                        ? 'Comprobante Autorizado Electrónicamente por ARCA'
                        : 'Documento de Control Interno sin Validez Fiscal',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
