import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart' as cloud_functions;
import 'package:http/http.dart' as http;
import 'producto_buffet_model.dart';
import '../tarifas/tarifa_model.dart';
import '../../theme/app_theme.dart';
import '../inventario/movimiento_stock_service.dart';
import '../../shared/mercado_pago_dialog.dart';
import '../../services/sugerencia_fiscal_service.dart';

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

  // 🚨 El bridge de WhatsApp (server.js) exige un ID token de Firebase de un
  // admin activo desde que se le agregó autenticación — estas llamadas
  // nunca mandaban el header y fallaban en silencio (401) desde entonces.
  Future<Map<String, String>> _headersWhatsapp() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  List<Map<String, dynamic>> _carrito = [];
  String? _socioSeleccionadoId;
  String _busquedaSocioPOS = "";
  Map<String, dynamic>? _socioSeleccionadoPOS;

  // 💸 Antes la búsqueda de socio en POS streameaba en vivo la colección
  // ENTERA de socios (.snapshots(), no .get()) y, como el stream se
  // recreaba en cada tecla presionada, cada letra tipeada volvía a leer
  // TODA la colección. Ahora se trae una sola vez al abrir la caja y la
  // búsqueda filtra en memoria — cero lecturas por tecla. "Actualizar" en
  // la lista de resultados permite refrescar si se dio de alta un socio
  // nuevo mientras la caja ya estaba abierta.
  List<QueryDocumentSnapshot> _todosLosSocios = [];
  bool _cargandoSocios = true;

  Future<void> _cargarSocios() async {
    setState(() => _cargandoSocios = true);
    final snap = await _firestore.collection('socios').get();
    if (mounted) {
      setState(() {
        _todosLosSocios = snap.docs;
        _cargandoSocios = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarSocios();
  }

  List<DocumentSnapshot> _reservasPendientesDelSocio = [];
  bool _buscandoReservas = false;

  String? _mesaSeleccionadaNombre;
  String? _sectorCajaSeleccionado;

  // 🧾 Selección de Tipo de Comprobante Fiscal en POS
  bool _emitirFacturaFiscal = false;

  double get totalCarrito {
    return _carrito.fold(
      0,
      (sum, item) => sum + (item['precio'] * item['cantidad']),
    );
  }

  // 📲 ENVÍO DE COMPROBANTE DE PAGO POR WHATSAPP
  Future<void> _enviarComprobantePorWhatsApp({
    required String telefono,
    required String nombreCliente,
    required List<Map<String, dynamic>> items,
    required double total,
    required String medioPago,
    String? cae,
  }) async {
    String limpio = telefono.replaceAll(RegExp(r'\D'), '');
    if (limpio.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('📄 *COMPROBANTE DE PAGO - OQUA CLUB DEPORTIVO*');
    buffer.writeln('----------------------------------------');
    buffer.writeln('👤 *Cliente:* $nombreCliente');
    buffer.writeln(
      '📍 *Punto de Venta (Caja):* ${_sectorCajaSeleccionado ?? "General"}',
    );
    buffer.writeln('💳 *Medio de Pago:* $medioPago');
    buffer.writeln(
      '🧾 *Tipo:* ${_emitirFacturaFiscal ? "Factura Fiscal ARCA (CAE: $cae)" : "Comprobante X (No Fiscal)"}',
    );
    buffer.writeln(
      '📅 *Fecha:* ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
    );
    buffer.writeln('----------------------------------------');
    buffer.writeln('*Detalle de Operación:*');

    for (var item in items) {
      buffer.writeln(
        '• ${item['nombre']} x${item['cantidad'] ?? 1}: \$${item['precio']} ARS',
      );
    }

    buffer.writeln('----------------------------------------');
    buffer.writeln('💰 *TOTAL ABONADO:* \$${total.toStringAsFixed(2)} ARS');
    buffer.writeln('\n¡Muchas gracias por tu compra!');

    try {
      final resp = await http.post(
        Uri.parse('https://servicio-whatsapp-oqua.onrender.com/send-whatsapp'),
        headers: await _headersWhatsapp(),
        body: jsonEncode({'phone': limpio, 'message': buffer.toString()}),
      );
      if (resp.statusCode != 200) {
        debugPrint('⚠️ Recibo WhatsApp no enviado (${resp.statusCode}): ${resp.body}');
        _avisarFalloWhatsapp('No se pudo enviar el recibo por WhatsApp.');
      }
    } catch (e) {
      debugPrint('⚠️ Error al enviar recibo por WhatsApp: $e');
      _avisarFalloWhatsapp('No se pudo enviar el recibo por WhatsApp.');
    }
  }

  // 🚨 Antes un envío de WhatsApp fallido sólo quedaba en debugPrint — en un
  // build de release eso es invisible, así que el cajero nunca se enteraba
  // de que el cliente no recibió su comprobante/aviso.
  void _avisarFalloWhatsapp(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('⚠️ $mensaje'), backgroundColor: Colors.orange),
    );
  }

  // 📊 DIÁLOGO Y PROCESO DE CIERRE DE CAJA CON REPORTE CONSOLIDADO
  Future<void> _mostrarDialogoCierreCaja(DocumentSnapshot docCaja) async {
    final dataCaja = docCaja.data() as Map<String, dynamic>;
    final double inicial =
        (dataCaja['montoInicialARS'] as num?)?.toDouble() ?? 0.0;
    final double efecARS =
        (dataCaja['totalEfectivoARS'] as num?)?.toDouble() ?? 0.0;
    final double efecUSD =
        (dataCaja['totalEfectivoUSD'] as num?)?.toDouble() ?? 0.0;
    final double mp = (dataCaja['totalMercadoPago'] as num?)?.toDouble() ?? 0.0;
    final double debito =
        (dataCaja['totalTarjetaDebito'] as num?)?.toDouble() ?? 0.0;
    final double credito =
        (dataCaja['totalTarjetaCredito'] as num?)?.toDouble() ?? 0.0;
    final double trans =
        (dataCaja['totalTransferencia'] as num?)?.toDouble() ?? 0.0;
    final double ctaCte = (dataCaja['totalCtaCte'] as num?)?.toDouble() ?? 0.0;

    // 🚨 efecARS ya incluye el monto inicial de apertura (se usa también para
    // conciliar el efectivo físico del cajón), así que se resta acá para que
    // "Total Recaudado" refleje ingresos reales del turno y no el float.
    final double totalGeneralRecaudado =
        (efecARS - inicial) + mp + debito + credito + trans;
    final TextEditingController obsCtrl = TextEditingController();
    final String operadorActual =
        dataCaja['usuario'] ?? 'Administrador Central';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 10),
            Text(
              'Cierre: Punto de Venta (Caja) ${_sectorCajaSeleccionado ?? "General"}',
            ),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Operador: $operadorActual',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                const Text(
                  'Resumen de Recaudación del Sector:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildLineaConsolidado(
                  'Monto Inicial Efectivo:',
                  '\$${inicial.toStringAsFixed(2)} ARS',
                ),
                _buildLineaConsolidado(
                  'Efectivo ARS en Caja:',
                  '\$${efecARS.toStringAsFixed(2)} ARS',
                ),
                _buildLineaConsolidado(
                  'Efectivo USD:',
                  '\$${efecUSD.toStringAsFixed(2)} USD',
                ),
                _buildLineaConsolidado(
                  'Mercado Pago:',
                  '\$${mp.toStringAsFixed(2)} ARS',
                ),
                _buildLineaConsolidado(
                  'Tarjeta Débito:',
                  '\$${debito.toStringAsFixed(2)} ARS',
                ),
                _buildLineaConsolidado(
                  'Tarjeta Crédito:',
                  '\$${credito.toStringAsFixed(2)} ARS',
                ),
                _buildLineaConsolidado(
                  'Transferencias:',
                  '\$${trans.toStringAsFixed(2)} ARS',
                ),
                _buildLineaConsolidado(
                  'Cuentas Corrientes:',
                  '\$${ctaCte.toStringAsFixed(2)} ARS',
                ),
                const Divider(),
                _buildLineaConsolidado(
                  'TOTAL RECAUDADO:',
                  '\$${totalGeneralRecaudado.toStringAsFixed(2)} ARS',
                  esTotal: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: obsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones de Cierre',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Volver'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
            ),
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
            label: const Text(
              'Cerrar Caja y Emitir Reporte',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () async {
              Navigator.pop(ctx);

              await _firestore
                  .collection('control_cajas')
                  .doc(docCaja.id)
                  .update({
                    'estado': 'Cerrada',
                    'fechaCierre': DateTime.now(),
                    'totalFinalGeneral': totalGeneralRecaudado,
                    'observacionesCierre': obsCtrl.text.trim(),
                  });

              if (_socioSeleccionadoPOS?['telefono'] != null) {
                await _enviarReporteConsolidadoWhatsApp(
                  telefono: _socioSeleccionadoPOS!['telefono'],
                  operador: operadorActual,
                  montoInicial: inicial,
                  efectivoARS: efecARS,
                  efectivoUSD: efecUSD,
                  mercadoPago: mp,
                  tarjetas: debito + credito,
                  transferencias: trans,
                  ctaCte: ctaCte,
                  totalGeneral: totalGeneralRecaudado,
                  observaciones: obsCtrl.text.trim(),
                );
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '🔒 CAJA CERRADA: Resumen emitido para ${_sectorCajaSeleccionado ?? "General"}.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLineaConsolidado(
    String etiqueta,
    String valor, {
    bool esTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            etiqueta,
            style: TextStyle(
              fontWeight: esTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: esTotal ? 15 : 13,
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: esTotal ? 16 : 13,
              color: esTotal ? Colors.green.shade800 : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarReporteConsolidadoWhatsApp({
    required String telefono,
    required String operador,
    required double montoInicial,
    required double efectivoARS,
    required double efectivoUSD,
    required double mercadoPago,
    required double tarjetas,
    required double transferencias,
    required double ctaCte,
    required double totalGeneral,
    required String observaciones,
  }) async {
    String limpio = telefono.replaceAll(RegExp(r'\D'), '');
    if (limpio.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln(
      '📊 *REPORTE CONSOLIDADO - CIERRE DE PUNTO DE VENTA (CAJA)*',
    );
    buffer.writeln('----------------------------------------');
    buffer.writeln(
      '📍 *Punto de Venta:* ${_sectorCajaSeleccionado ?? "General"}',
    );
    buffer.writeln('👤 *Operador:* $operador');
    buffer.writeln(
      '📅 *Fecha:* ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute} hs',
    );
    buffer.writeln('----------------------------------------');
    buffer.writeln(
      '• *Monto Inicial:* \$${montoInicial.toStringAsFixed(2)} ARS',
    );
    buffer.writeln(
      '• *Efectivo en Caja:* \$${efectivoARS.toStringAsFixed(2)} ARS',
    );
    if (efectivoUSD > 0)
      buffer.writeln(
        '• *Efectivo USD:* \$${efectivoUSD.toStringAsFixed(2)} USD',
      );
    buffer.writeln('• *Mercado Pago:* \$${mercadoPago.toStringAsFixed(2)} ARS');
    buffer.writeln('• *Tarjetas:* \$${tarjetas.toStringAsFixed(2)} ARS');
    buffer.writeln(
      '• *Transferencias:* \$${transferencias.toStringAsFixed(2)} ARS',
    );
    buffer.writeln('• *Cta Cte:* \$${ctaCte.toStringAsFixed(2)} ARS');
    buffer.writeln('----------------------------------------');
    buffer.writeln(
      '💰 *TOTAL RECAUDADO:* \$${totalGeneral.toStringAsFixed(2)} ARS',
    );
    if (observaciones.isNotEmpty) buffer.writeln('\n📝 *Obs:* $observaciones');

    try {
      final resp = await http.post(
        Uri.parse('https://servicio-whatsapp-oqua.onrender.com/send-whatsapp'),
        headers: await _headersWhatsapp(),
        body: jsonEncode({'phone': limpio, 'message': buffer.toString()}),
      );
      if (resp.statusCode != 200) {
        debugPrint('⚠️ Consolidado WhatsApp no enviado (${resp.statusCode}): ${resp.body}');
        _avisarFalloWhatsapp('No se pudo enviar el consolidado de cierre de caja.');
      }
    } catch (e) {
      debugPrint('Error enviando consolidado: $e');
      _avisarFalloWhatsapp('No se pudo enviar el consolidado de cierre de caja.');
    }
  }

  void _editarPrecioItem(int index) {
    final item = _carrito[index];
    final controller = TextEditingController(
      text: item['precio'].toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Valor: ${item['nombre']}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Monto Personalizado (\$)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final nuevoMonto =
                  double.tryParse(controller.text) ?? item['precio'];
              setState(() => _carrito[index]['precio'] = nuevoMonto);
              Navigator.pop(ctx);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
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
      if (!mounted) return;
      setState(() {
        _reservasPendientesDelSocio = snapshot.docs;
        _buscandoReservas = false;
      });
    } catch (e) {
      if (mounted) setState(() => _buscandoReservas = false);
    }
  }

  void _cargarReservaAlCarrito(DocumentSnapshot docVenta) {
    final data = docVenta.data() as Map<String, dynamic>;
    final List<dynamic> itemsReserva = data['items'] ?? [];
    setState(() {
      for (var item in itemsReserva) {
        _carrito.add({
          'id': item['id'] ?? docVenta.id,
          'nombre': item['nombre'] ?? 'Reserva de Cancha / Turno Paddle',
          'precio': (item['precio'] as num).toDouble(),
          'cantidad': item['cantidad'] ?? 1,
          'es_producto_fisico': false,
          'origen_pendiente_id': docVenta.id,
        });
      }
    });
  }

  Future<void> _verificarMatriculaAnual(String socioId) async {
    final anioActual = DateTime.now().year.toString();

    final docMatricula = await _firestore
        .collection('socios')
        .doc(socioId)
        .collection('matriculas_pagas')
        .doc(anioActual)
        .get();

    if (!docMatricula.exists) {
      final docConfig = await _firestore
          .collection('configuracion')
          .doc('matricula_anual')
          .get();
      final double montoMatricula =
          (docConfig.data()?['monto'] as num?)?.toDouble() ?? 20000.0;

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.badge, color: Colors.amber),
                SizedBox(width: 8),
                Text('Matrícula Anual Pendiente'),
              ],
            ),
            content: Text(
              'El socio no posee registrada la Matrícula Anual $anioActual (\$$montoMatricula ARS).\n\n¿Deseas incluirla en esta operación?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Omitir'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _carrito.add({
                      'id': 'matricula_$anioActual',
                      'nombre': 'Matrícula Anual $anioActual',
                      'precio': montoMatricula,
                      'cantidad': 1,
                      'es_producto_fisico': false,
                      'esMatricula': true,
                      'anioMatricula': anioActual,
                    });
                  });
                },
                child: const Text(
                  'Agregar Matrícula',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<TarifaModel?> _obtenerTarifaVigente({
    required String deporte,
    required String frecuencia,
  }) async {
    try {
      final query = await _firestore
          .collection('tarifas')
          .where('deporte', isEqualTo: deporte)
          .where('frecuencia', isEqualTo: frecuencia)
          .get();

      final hoy = DateTime.now();
      for (var doc in query.docs) {
        final tarifa = TarifaModel.fromFirestore(doc.id, doc.data());
        if (tarifa.esVigenteEn(hoy)) return tarifa;
      }
    } catch (e) {
      print("Error obteniendo tarifa: $e");
    }
    return null;
  }

  Future<void> _verificarYAgregarCuotaSocial(
    Map<String, dynamic> socioData,
    String socioId,
  ) async {
    final hoy = DateTime.now();

    List<String> periodosDisponibles = List.generate(6, (i) {
      final fecha = DateTime(hoy.year, hoy.month + i, 1);
      return "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}";
    });

    String periodoSeleccionado = periodosDisponibles.first;

    final tarifa = await _obtenerTarifaVigente(
      deporte: socioData['deporte'] ?? 'Socio Natatorio',
      frecuencia: socioData['frecuencia'] ?? 'Pase Libre',
    );

    double precioRegular = tarifa?.precioRegular ?? 15000.0;
    double precioEfectivo = tarifa?.precioEfectivo ?? precioRegular;

    if (socioData['esEstudianteEscuela'] == true) {
      final double dto =
          (socioData['descuentoEscolarPorcentaje'] as num?)?.toDouble() ?? 0.0;
      if (dto > 0) {
        precioRegular -= (precioRegular * (dto / 100));
        precioEfectivo -= (precioEfectivo * (dto / 100));
      }
    }

    const nombresMeses = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Cobro de Cuota Social'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Socio: ${socioData['nombre'] ?? ''}\n• Precio Regular: \$${precioRegular.toStringAsFixed(0)} ARS\n• Descuento Efectivo: \$${precioEfectivo.toStringAsFixed(0)} ARS',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: periodoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Período a Abonar',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                    ),
                    items: periodosDisponibles.map((p) {
                      final partes = p.split('-');
                      final anio = partes[0];
                      final mesNum = int.parse(partes[1]);
                      final nombreMes = nombresMeses[mesNum - 1];
                      return DropdownMenuItem(
                        value: p,
                        child: Text('$nombreMes $anio ($p)'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null)
                        setModalState(() => periodoSeleccionado = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Omitir'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _carrito.add({
                        'id': 'cuota_$periodoSeleccionado',
                        'nombre': 'Cuota Social $periodoSeleccionado',
                        'precio': precioRegular,
                        'precioRegularAuto': precioRegular,
                        'precioEfectivoAuto': precioEfectivo,
                        'cantidad': 1,
                        'es_producto_fisico': false,
                        'esCuotaSocial': true,
                        'mesPeriodo': periodoSeleccionado,
                      });
                    });
                  },
                  child: const Text(
                    'Agregar Cuota al Ticket',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📊 Cuenta de $_mesaSeleccionadaNombre guardada.'),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }
    } catch (e) {
      print("Error guardando mesa: $e");
    }
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
                hintText: 'Vincular Socio / Cliente por Nombre o DNI...',
                prefixIcon: Icon(Icons.person_search_rounded),
                border: InputBorder.none,
              ),
              onChanged: (val) => setState(() => _busquedaSocioPOS = val),
            ),
            if (_busquedaSocioPOS.length >= 2) _buildListaResultadosSocios(),
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
                      'Socio Vinculado: ${_socioSeleccionadoPOS!['nombre'] ?? ''}',
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
    if (_cargandoSocios) return const LinearProgressIndicator();

    final query = _busquedaSocioPOS.toLowerCase().trim();
    final docs = _todosLosSocios.where((d) {
      final data = d.data() as Map<String, dynamic>? ?? {};
      final String n = (data['nombre'] ?? '').toString().toLowerCase();
      final String dni = (data['dni'] ?? '').toString().toLowerCase();
      return n.contains(query) || dni.contains(query);
    }).toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _cargarSocios,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Actualizar', style: TextStyle(fontSize: 11)),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final d = docs[i];
                final data = d.data() as Map<String, dynamic>;

                return ListTile(
                  title: Text(data['nombre'] ?? ''),
                  subtitle: Text(
                    'DNI: ${data['dni'] ?? 'S/D'} • Actividad: ${data['deporte'] ?? 'Natatorio'}',
                  ),
                  onTap: () {
                    setState(() {
                      _socioSeleccionadoId = d.id;
                      _socioSeleccionadoPOS = data;
                      _busquedaSocioPOS = "";
                    });
                    _buscarReservasPendientes(d.id);
                    _verificarMatriculaAnual(d.id);
                    _verificarYAgregarCuotaSocial(data, d.id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAperturaCajaDirecta({bool esCobroAutomatico = false}) {
    final TextEditingController montoInicialCtrl = TextEditingController(
      text: '0',
    );
    final userActual = FirebaseAuth.instance.currentUser;
    final String nombreOperador =
        userActual?.displayName ?? userActual?.email ?? 'Administrador Central';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.point_of_sale_rounded,
              color: Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              esCobroAutomatico
                  ? 'Apertura: Punto de Venta (Caja) ${_sectorCajaSeleccionado ?? "General"}'
                  : 'Apertura de Punto de Venta (Caja)',
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresá el saldo inicial en efectivo para habilitar ${_sectorCajaSeleccionado ?? "el Punto de Venta (Caja)"} (Operador: $nombreOperador):',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: montoInicialCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Monto Inicial Efectivo ARS (\$)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            onPressed: () async {
              final double montoInicial =
                  double.tryParse(montoInicialCtrl.text) ?? 0.0;

              await _firestore.collection('control_cajas').add({
                'nombreCajaTerminal':
                    _sectorCajaSeleccionado ?? 'Punto de Venta (Caja) Central',
                'usuario': nombreOperador,
                'usuarioUid': userActual?.uid ?? 'anonimo',
                'fechaApertura': DateTime.now(),
                'montoInicialARS': montoInicial,
                'saldoInicialARS': montoInicial,
                'estado': 'Abierta',
                'totalEfectivoARS': montoInicial,
                'totalEfectivoUSD': 0.0,
                'totalMercadoPago': 0.0,
                'totalTarjetaDebito': 0.0,
                'totalTarjetaCredito': 0.0,
                'totalTransferencia': 0.0,
                'totalCtaCte': 0.0,
              });

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '🟢 PUNTO DE VENTA ABIERTO: ${_sectorCajaSeleccionado ?? "Caja"} iniciado con \$${montoInicial.toStringAsFixed(0)} ARS por $nombreOperador.',
                  ),
                  backgroundColor: Colors.green.shade800,
                ),
              );
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);

              if (esCobroAutomatico) _mostrarDialogoCobro();
            },
            child: const Text(
              'Abrir Caja y Continuar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verificarYProcesarCobro() async {
    if (_carrito.isEmpty) return;
    if (_sectorCajaSeleccionado == null) return;

    final userActual = FirebaseAuth.instance.currentUser;
    final String uidActual = userActual?.uid ?? 'anonimo';

    final cajaQuery = await _firestore
        .collection('control_cajas')
        .where('nombreCajaTerminal', isEqualTo: _sectorCajaSeleccionado)
        .where('estado', isEqualTo: 'Abierta')
        .limit(1)
        .get();

    if (cajaQuery.docs.isEmpty) {
      _mostrarDialogoAperturaCajaDirecta(esCobroAutomatico: true);
      return;
    }

    if (!mounted) return;

    final docCaja = cajaQuery.docs.first;
    final dataCaja = docCaja.data();
    final String uidOperadorCaja = dataCaja['usuarioUid'] ?? '';
    final String nombreOperadorCaja = dataCaja['usuario'] ?? 'Otro operador';

    if (uidOperadorCaja != uidActual) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.gpp_bad_rounded, color: Colors.red, size: 28),
                SizedBox(width: 10),
                Text('Punto de Venta Bloqueado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'El Punto de Venta (Caja) $_sectorCajaSeleccionado está siendo operada por:\n👤 $nombreOperadorCaja',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Podés seleccionar otro Punto de Venta (Caja) disponible en el menú desplegable superior o solicitar el cierre de turno.',
                  style: TextStyle(color: Colors.black87, fontSize: 13),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cambiar Punto de Venta',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }

    _mostrarDialogoCobro();
  }

  Future<void> _mostrarDialogoCobro() async {
    String medioPagoSeleccionado = 'Efectivo ARS';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(
            'Procesar Cobro: Punto de Venta (Caja) $_sectorCajaSeleccionado',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total: \$${totalCarrito.toStringAsFixed(2)} ARS',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: medioPagoSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Medio de Pago',
                  border: OutlineInputBorder(),
                ),
                items:
                    [
                          'Efectivo ARS',
                          'Cuenta Corriente',
                          'Efectivo USD',
                          'Mercado Pago',
                          'Tarjeta Débito',
                          'Tarjeta Crédito',
                          'Transferencia Bancaria',
                        ]
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                onChanged: (val) {
                  setModalState(() {
                    medioPagoSeleccionado = val!;
                    for (var item in _carrito) {
                      if (item['esCuotaSocial'] == true) {
                        if (medioPagoSeleccionado.contains('Efectivo')) {
                          item['precio'] =
                              item['precioEfectivoAuto'] ?? item['precio'];
                        } else {
                          item['precio'] =
                              item['precioRegularAuto'] ?? item['precio'];
                        }
                      }
                    }
                    // 🧾 Sugiere factura fiscal para medios electrónicos y
                    // comprobante X para efectivo/cta.cte — el operador
                    // puede seguir tildando/destildando el switch a mano.
                    _emitirFacturaFiscal = esMedioPagoElectronico(
                      medioPagoSeleccionado,
                    );
                  });
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(
                  _emitirFacturaFiscal
                      ? 'Emitir Factura Fiscal ARCA (Oficial)'
                      : 'Comprobante X (No Fiscal)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  _emitirFacturaFiscal
                      ? 'Solicita CAE a ARCA'
                      : 'No genera impacto impositivo',
                ),
                value: _emitirFacturaFiscal,
                activeColor: Colors.indigo,
                onChanged: (v) => setModalState(() => _emitirFacturaFiscal = v),
              ),
            ],
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
                Navigator.pop(context);
                await _procesarVentaFirestore(medioPagoSeleccionado);
              },
              child: const Text(
                'Confirmar Cobro',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ⚠️ Aviso (no bloqueante) de stock insuficiente antes de cobrar: el
  // cajero decide si continúa o cancela la venta.
  Future<bool> _confirmarVentaConStockInsuficiente(List<String> avisos) async {
    if (!mounted) return false;
    final bool? continuar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('Stock insuficiente'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Los siguientes productos no tienen stock suficiente:',
            ),
            const SizedBox(height: 12),
            ...avisos.map(
              (a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Text('• $a', style: const TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '¿Continuar de todas formas? El stock quedará en negativo.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar Venta'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Continuar Igual',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    return continuar ?? false;
  }

  // 🔄 PROCESAMIENTO CON DESCUENTO DE STOCK DINÁMICO POR RECETA / COMBOS
  Future<void> _procesarVentaFirestore(String medio) async {
    final cajaQuery = await _firestore
        .collection('control_cajas')
        .where('nombreCajaTerminal', isEqualTo: _sectorCajaSeleccionado)
        .where('estado', isEqualTo: 'Abierta')
        .limit(1)
        .get();

    if (!mounted) return;

    if (cajaQuery.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ Abrí el Punto de Venta (Caja) $_sectorCajaSeleccionado antes de cobros.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final docCajaId = cajaQuery.docs.first.id;

    final List<Map<String, dynamic>> itemsCobrados = List.from(_carrito);
    final double totalVentaActual = totalCarrito;
    final Map<String, dynamic>? datosSocioActual = _socioSeleccionadoPOS;

    // 🚀 Trae en un puñado de consultas (en vez de una por línea de ticket)
    // todos los productos físicos del carrito y, si son combos, sus
    // insumos — esto también permite avisar de stock insuficiente ANTES de
    // cobrar, en vez de simplemente dejar que stockActual caiga en negativo
    // sin ningún aviso.
    final List<String> idsProductosFisicos = _carrito
        .where(
          (it) =>
              it['es_producto_fisico'] == true &&
              (it['id'] as String? ?? '').isNotEmpty,
        )
        .map((it) => it['id'] as String)
        .toSet()
        .toList();

    final Map<String, Map<String, dynamic>> prodDataPorId = {};
    Future<void> cargarEnLotesDe30(List<String> ids) async {
      for (var i = 0; i < ids.length; i += 30) {
        final lote = ids.sublist(
          i,
          (i + 30 > ids.length) ? ids.length : i + 30,
        );
        final snap = await _firestore
            .collection('inventario_general')
            .where(FieldPath.documentId, whereIn: lote)
            .get();
        for (var doc in snap.docs) {
          prodDataPorId[doc.id] = doc.data();
        }
      }
    }

    if (idsProductosFisicos.isNotEmpty) {
      await cargarEnLotesDe30(idsProductosFisicos);
    }

    final Set<String> idsComponentes = {};
    for (var id in idsProductosFisicos) {
      final prodData = prodDataPorId[id];
      if (prodData != null && prodData['esCombo'] == true) {
        for (var comp in (prodData['componentes'] as List<dynamic>? ?? [])) {
          final String subId =
              comp['productoId'] ?? comp['itemInventarioId'] ?? '';
          if (subId.isNotEmpty) idsComponentes.add(subId);
        }
      }
    }
    final idsComponentesFaltantes = idsComponentes
        .where((id) => !prodDataPorId.containsKey(id))
        .toList();
    if (idsComponentesFaltantes.isNotEmpty) {
      await cargarEnLotesDe30(idsComponentesFaltantes);
    }

    // 🚨 Aviso de stock insuficiente: no bloquea la venta (el cajero puede
    // decidir continuar igual), sólo advierte antes de cobrar.
    final List<String> avisosStock = [];
    for (var item in _carrito) {
      if (item['es_producto_fisico'] != true) continue;
      final String itemId = item['id'] ?? '';
      final int cantidadComprada = item['cantidad'] ?? 1;
      final prodData = prodDataPorId[itemId];
      if (prodData == null) continue;

      if (prodData['esCombo'] == true) {
        for (var comp in (prodData['componentes'] as List<dynamic>? ?? [])) {
          final String subId =
              comp['productoId'] ?? comp['itemInventarioId'] ?? '';
          final subData = prodDataPorId[subId];
          if (subData == null) continue;
          final int cantComponente = (comp['cantidad'] as num?)?.toInt() ?? 1;
          final double stockSub =
              (subData['stockActual'] as num?)?.toDouble() ?? 0;
          final int totalBaja = cantComponente * cantidadComprada;
          if (totalBaja > stockSub) {
            avisosStock.add(
              '${subData['nombre'] ?? subId} (insumo de ${item['nombre']}): quedan ${stockSub.toStringAsFixed(0)}, se necesitan $totalBaja',
            );
          }
        }
      } else {
        final double stock = (prodData['stockActual'] as num?)?.toDouble() ?? 0;
        if (cantidadComprada > stock) {
          avisosStock.add(
            '${item['nombre']}: quedan ${stock.toStringAsFixed(0)}, se piden $cantidadComprada',
          );
        }
      }
    }

    if (avisosStock.isNotEmpty) {
      final bool continuar = await _confirmarVentaConStockInsuficiente(
        avisosStock,
      );
      if (!continuar) return;
    }

    WriteBatch batch = _firestore.batch();
    // 🚨 Se genera acá (antes de la venta) para poder referenciarla como
    // 'referencia' en los movimientos_stock que se registran en el mismo
    // batch, sin depender del orden en que Firestore asigna IDs.
    final DocumentReference ventaRefParaMovimientos = _firestore
        .collection('ventas_buffet')
        .doc();
    final String usuarioActualPos =
        FirebaseAuth.instance.currentUser?.email ?? 'Caja';

    for (var item in _carrito) {
      final String itemId = item['id'];
      final int cantidadComprada = item['cantidad'] ?? 1;

      // 1. Matrícula
      if (item['esMatricula'] == true && _socioSeleccionadoId != null) {
        DocumentReference matRef = _firestore
            .collection('socios')
            .doc(_socioSeleccionadoId!)
            .collection('matriculas_pagas')
            .doc(item['anioMatricula']);
        batch.set(matRef, {
          'fecha': DateTime.now(),
          'monto': item['precio'],
          'medioPago': medio,
        });
        DocumentReference socioRef = _firestore
            .collection('socios')
            .doc(_socioSeleccionadoId!);
        batch.update(socioRef, {
          'matriculaAlDia': true,
          'fechaPagoMatricula': DateTime.now(),
        });
      }

      // 2. Cuota Social
      if (item['esCuotaSocial'] == true && _socioSeleccionadoId != null) {
        DocumentReference cuotaPagaRef = _firestore
            .collection('socios')
            .doc(_socioSeleccionadoId!)
            .collection('cuotas_pagas')
            .doc(item['mesPeriodo']);
        batch.set(cuotaPagaRef, {
          'fechaPago': DateTime.now(),
          'monto': item['precio'],
          'periodo': item['mesPeriodo'],
        });
        DocumentReference socioRef = _firestore
            .collection('socios')
            .doc(_socioSeleccionadoId!);
        batch.update(socioRef, {'ultimoMesPago': item['mesPeriodo']});
      }

      // 3. Reserva / Turno Pendiente
      if (item['origen_pendiente_id'] != null) {
        DocumentReference resRef = _firestore
            .collection('ventas_pendientes')
            .doc(item['origen_pendiente_id']);
        batch.update(resRef, {
          'estado': 'Cobrado',
          'fechaCobro': DateTime.now(),
        });
      }

      // 🍔 4. DESCUENTO DE STOCK DINÁMICO (PRODUCTO SIMPLE O COMBO / RECETA)
      if (item['es_producto_fisico'] == true && itemId.isNotEmpty) {
        final prodData = prodDataPorId[itemId];
        if (prodData != null) {
          final bool esComboReceta = prodData['esCombo'] == true;
          final List<dynamic> componentes = prodData['componentes'] ?? [];

          if (esComboReceta && componentes.isNotEmpty) {
            // 🔄 DESCUENTO DINÁMICO DE CADA INSUMO / RECETA
            for (var comp in componentes) {
              // 🚨 Combos creados desde "Central de Inventario" guardan la
              // clave vieja 'itemInventarioId' en vez de 'productoId'.
              final String subProdId =
                  comp['productoId'] ?? comp['itemInventarioId'] ?? '';
              final int cantComponente =
                  (comp['cantidad'] as num?)?.toInt() ?? 1;
              if (subProdId.isNotEmpty) {
                final int totalBajaInsumo = cantComponente * cantidadComprada;
                DocumentReference subProdRef = _firestore
                    .collection('inventario_general')
                    .doc(subProdId);
                batch.update(subProdRef, {
                  'stockActual': FieldValue.increment(-totalBajaInsumo),
                });
                MovimientoStockService.registrarMovimientoEnBatch(
                  batch,
                  productoId: subProdId,
                  productoNombre: 'Insumo de ${item['nombre']}',
                  tipo: 'Venta POS (combo)',
                  cantidad: -totalBajaInsumo,
                  referencia: ventaRefParaMovimientos.id,
                  usuario: usuarioActualPos,
                );
              }
            }
          } else {
            // 📦 DESCUENTO DE ARTÍCULO INDIVIDUAL DIRECTO
            DocumentReference prodRef = _firestore
                .collection('inventario_general')
                .doc(itemId);
            batch.update(prodRef, {
              'stockActual': FieldValue.increment(-cantidadComprada),
            });
            MovimientoStockService.registrarMovimientoEnBatch(
              batch,
              productoId: itemId,
              productoNombre: item['nombre'] ?? prodData['nombre'] ?? itemId,
              tipo: 'Venta POS',
              cantidad: -cantidadComprada,
              referencia: ventaRefParaMovimientos.id,
              usuario: usuarioActualPos,
            );
          }

          // Guardar metadatos en el ítem del carrito para la comanda de cocina
          item['requiereCocina'] = prodData['requiereCocina'] ?? false;
          item['componentes'] = componentes;
        }
      }
    }

    String? caeFactura;
    String? vencimientoCaeFactura;
    num? nroFacturaLegal;
    num? puntoVentaLegal;
    num? tipoComprobanteLegal;
    if (_emitirFacturaFiscal) {
      try {
        // 🧾 Concepto AFIP: el carrito puede mezclar productos (buffet) con
        // servicios (cuota social/matrícula) — 1=Productos, 2=Servicios,
        // 3=Ambos. Antes esto siempre mandaba Concepto=1 sin importar qué
        // se estuviera cobrando.
        final bool tieneServicio = _carrito.any(
          (it) => it['esCuotaSocial'] == true || it['esMatricula'] == true,
        );
        final bool tieneProducto = _carrito.any(
          (it) => it['esCuotaSocial'] != true && it['esMatricula'] != true,
        );
        final int concepto = tieneServicio && tieneProducto
            ? 3
            : (tieneServicio ? 2 : 1);

        final callable = cloud_functions.FirebaseFunctions.instance
            .httpsCallable('emitirFacturaArca');
        final resp = await callable.call({
          'total': totalCarrito,
          'socioDni': _socioSeleccionadoPOS?['dni'] ?? '',
          'concepto': concepto,
        });
        if (resp.data['success'] == true) {
          caeFactura = resp.data['cae'];
          vencimientoCaeFactura = resp.data['vencimientoCae'];
          nroFacturaLegal = resp.data['nroFactura'];
          puntoVentaLegal = resp.data['puntoVenta'];
          tipoComprobanteLegal = resp.data['tipoComprobante'];
        }
      } catch (e) {
        print("Error al solicitar CAE: $e");
      }
    }

    final DocumentReference ventaRef = ventaRefParaMovimientos;
    batch.set(ventaRef, {
      'items': _carrito,
      'total': totalCarrito,
      'medio_pago': medio,
      'nombreCajaTerminal': _sectorCajaSeleccionado,
      'cajaId': docCajaId,
      'fecha': DateTime.now(),
      'socio_id': _socioSeleccionadoId,
      'origen_salón': _mesaSeleccionadaNombre ?? 'Mostrador Directo',
      'usuario': FirebaseAuth.instance.currentUser?.email ?? 'Administrador Central',
      'fiscalizado': _emitirFacturaFiscal && caeFactura != null,
      'cae': caeFactura ?? (_emitirFacturaFiscal ? 'ERROR_CAE' : 'NO_FISCAL_X'),
      // 🧾 Antes sólo se guardaba el CAE: el explorador de ventas mostraba
      // N° de comprobante y vencimiento de CAE con valores de relleno
      // (0001-00000000) incluso para facturas realmente autorizadas.
      if (vencimientoCaeFactura != null) 'vencimientoCae': vencimientoCaeFactura,
      if (nroFacturaLegal != null) 'nroFacturaLegal': nroFacturaLegal,
      if (puntoVentaLegal != null) 'puntoVentaLegal': puntoVentaLegal,
      if (tipoComprobanteLegal != null) 'tipoComprobanteLegal': tipoComprobanteLegal,
      'estadoCocina': _carrito.any((it) => it['requiereCocina'] == true)
          ? 'Pendiente'
          : 'Entregado',
    });

    if (medio == 'Cuenta Corriente' && _socioSeleccionadoId != null) {
      DocumentReference ctaCteRef = _firestore
          .collection('socios')
          .doc(_socioSeleccionadoId!)
          .collection('cuenta_corriente')
          .doc();
      batch.set(ctaCteRef, {
        'fecha': DateTime.now(),
        'tipo': 'Consumo POS',
        'monto': -totalCarrito,
        'detalle':
            'Consumo asignado a Cuenta Corriente en Punto de Venta (Caja) $_sectorCajaSeleccionado',
      });
      DocumentReference socioRef = _firestore
          .collection('socios')
          .doc(_socioSeleccionadoId!);
      batch.update(socioRef, {
        'saldoCuentaCorriente': FieldValue.increment(-totalCarrito),
      });
    }

    String campoIncrementar = 'totalEfectivoARS';
    if (medio == 'Efectivo USD') campoIncrementar = 'totalEfectivoUSD';
    if (medio == 'Mercado Pago') campoIncrementar = 'totalMercadoPago';
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

    await batch.commit();

    // 🧾💳 MERCADO PAGO REAL: antes "Mercado Pago" era sólo una etiqueta que
    // el cajero tildaba a mano, sin ninguna verificación — crearCobroMercadoPago
    // (genera una preferencia de Checkout Pro) y webhookMercadoPago (valida el
    // pago contra la API de MP) ya existían en el backend pero nada los
    // llamaba. Ahora, al cobrar con Mercado Pago, se muestra el QR/link real
    // y se espera la confirmación del webhook antes de dar la venta por
    // cobrada de verdad.
    if (medio == 'Mercado Pago' && mounted) {
      await mostrarSelectorCobroMercadoPago(
        context,
        ruta: 'ventas_buffet/${ventaRef.id}',
        campoMonto: 'total',
        campoMedioPago: 'medio_pago',
        concepto: itemsCobrados.isNotEmpty
            ? '${itemsCobrados.length} ítem(s) - $_sectorCajaSeleccionado'
            : 'Consumo Aqua & Paddle Club',
      );
    }

    final String? telefonoSocio = datosSocioActual?['telefono'] as String?;
    final String nombreCliente =
        datosSocioActual?['nombre'] ?? 'Mostrador Directo';

    if (telefonoSocio != null && telefonoSocio.isNotEmpty) {
      _enviarComprobantePorWhatsApp(
        telefono: telefonoSocio,
        nombreCliente: nombreCliente,
        items: itemsCobrados,
        total: totalVentaActual,
        medioPago: medio,
        cae: caeFactura,
      );
    }

    if (mounted) {
      setState(() {
        _carrito.clear();
        _socioSeleccionadoId = null;
        _socioSeleccionadoPOS = null;
        _mesaSeleccionadaNombre = null;
        _reservasPendientesDelSocio = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Cobro registrado y comprobante emitido'),
          backgroundColor: Colors.green,
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 🏢 MAESTRO DE CAJAS DINÁMICO DESDE FIRESTORE
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('terminales_caja')
                            .snapshots(),
                        builder: (context, snapshot) {
                          List<String> opcionesCajas = [
                            'Punto de Venta (Caja) Central',
                          ];
                          if (snapshot.hasData &&
                              snapshot.data!.docs.isNotEmpty) {
                            opcionesCajas = snapshot.data!.docs
                                .map(
                                  (doc) =>
                                      (doc.data()
                                              as Map<String, dynamic>)['nombre']
                                          as String? ??
                                      '',
                                )
                                .where((n) => n.isNotEmpty)
                                .toList();
                          }

                          if (_sectorCajaSeleccionado == null ||
                              (!opcionesCajas.contains(
                                    _sectorCajaSeleccionado,
                                  ) &&
                                  opcionesCajas.isNotEmpty)) {
                            _sectorCajaSeleccionado = opcionesCajas.first;
                          }

                          return DropdownButton<String>(
                            value: _sectorCajaSeleccionado,
                            icon: const Icon(
                              Icons.arrow_drop_down_circle_outlined,
                              color: Color(0xFF0F172A),
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                            underline: Container(),
                            onChanged: (String? nuevoSector) {
                              if (nuevoSector != null)
                                setState(
                                  () => _sectorCajaSeleccionado = nuevoSector,
                                );
                            },
                            items: opcionesCajas.map((String sector) {
                              return DropdownMenuItem<String>(
                                value: sector,
                                child: Text('Punto de Venta (Caja): $sector'),
                              );
                            }).toList(),
                          );
                        },
                      ),

                      // 🛡️ CHIP DE ESTADO DINÁMICO DE LA CAJA SELECCIONADA
                      if (_sectorCajaSeleccionado != null)
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('control_cajas')
                              .where(
                                'nombreCajaTerminal',
                                isEqualTo: _sectorCajaSeleccionado,
                              )
                              .where('estado', isEqualTo: 'Abierta')
                              .snapshots(),
                          builder: (context, snapshot) {
                            final userActual =
                                FirebaseAuth.instance.currentUser;
                            final bool hayCajaAbierta =
                                snapshot.hasData &&
                                snapshot.data!.docs.isNotEmpty;

                            String textoEstado = 'Caja Cerrada';
                            Color colorEstado = Colors.orange;
                            bool esMiCaja = false;

                            if (hayCajaAbierta) {
                              final data =
                                  snapshot.data!.docs.first.data()
                                      as Map<String, dynamic>;
                              final uidCaja = data['usuarioUid'];
                              final operadorNombre =
                                  data['usuario'] ?? 'Operador';

                              if (uidCaja == userActual?.uid) {
                                textoEstado = 'Abierta (Tu Turno)';
                                colorEstado = Colors.green;
                                esMiCaja = true;
                              } else {
                                textoEstado = 'Bloqueada: $operadorNombre';
                                colorEstado = Colors.red;
                              }
                            }

                            return ActionChip(
                              avatar: Icon(
                                hayCajaAbierta
                                    ? (esMiCaja
                                          ? Icons.check_circle_rounded
                                          : Icons.lock_rounded)
                                    : Icons.lock_clock_rounded,
                                color: colorEstado,
                                size: 20,
                              ),
                              label: Text(
                                textoEstado,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorEstado,
                                ),
                              ),
                              backgroundColor: colorEstado.withOpacity(0.1),
                              side: BorderSide(
                                color: colorEstado.withOpacity(0.3),
                              ),
                              onPressed: () {
                                if (!hayCajaAbierta) {
                                  _mostrarDialogoAperturaCajaDirecta(
                                    esCobroAutomatico: false,
                                  );
                                } else if (esMiCaja) {
                                  _mostrarDialogoCierreCaja(
                                    snapshot.data!.docs.first,
                                  );
                                } else {
                                  _verificarYProcesarCobro();
                                }
                              },
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildMapaMesasSalon(),
                  const SizedBox(height: 16),
                  _buildBuscadorSocios(),

                  if (_buscandoReservas)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: LinearProgressIndicator(color: Colors.orange),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🎾 Turno / Reserva Pendiente (${data['origen'] ?? 'Paddle'})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                                Text(
                                  'Detalle: ${items.map((i) => i['nombre']).join(", ")}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  '\$${totalReserva.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade800,
                                  ),
                                  onPressed: () => _cargarReservaAlCarrito(doc),
                                  icon: const Icon(
                                    Icons.add_shopping_cart,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Cargar al Ticket',
                                    style: TextStyle(color: Colors.white),
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
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('inventario_general')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const CircularProgressIndicator();
                        // 🚨 'disponible' se escribe (toggle manual y
                        // auto-desactivación por stock 0 en Central de
                        // Inventario) pero antes no se leía acá: un producto
                        // deshabilitado seguía vendible indefinidamente en el
                        // punto de venta.
                        final docs = snapshot.data!.docs.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          return data['disponible'] != false;
                        }).toList();

                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.95,
                              ),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final p = ProductoBuffetModel.fromFirestore(
                              docs[i],
                            );
                            // 🎨 Antes: Card+Center+Column con sólo nombre y
                            // precio, sin ninguna otra señal visual (combo,
                            // stock bajo, categoría). Ahora la grilla da la
                            // misma jerarquía y feedback que el resto del
                            // rediseño (chip de categoría, badge de combo/
                            // stock bajo, precio como protagonista).
                            final bool stockBajo =
                                !p.esCombo && p.stock <= p.stockMinimo;
                            return Material(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(
                                AppRadius.md,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                onTap: () {
                                  setState(() {
                                    _carrito.add({
                                      'id': p.id,
                                      'nombre': p.nombre,
                                      'precio': p.precio,
                                      'cantidad': 1,
                                      'es_producto_fisico': true,
                                    });
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    border: Border.all(color: AppColors.line),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.categoria,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textMuted,
                                                letterSpacing: 0.3,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (p.esCombo)
                                            const Icon(
                                              Icons.fastfood_rounded,
                                              size: 14,
                                              color: AppColors.teal,
                                            )
                                          else if (stockBajo)
                                            const Icon(
                                              Icons.error_outline_rounded,
                                              size: 14,
                                              color: AppColors.warning,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: Text(
                                          p.nombre,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '\$${p.precio.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.tealDark,
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
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(left: BorderSide(color: AppColors.line)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_rounded,
                        color: AppColors.navy,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Resumen de Ticket',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      if (_carrito.isNotEmpty)
                        StatusBadge(
                          label: '${_carrito.length} ítems',
                          color: AppColors.teal,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _carrito.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 40,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'El ticket está vacío',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _carrito.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final item = _carrito[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['nombre'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '\$${item['precio']} c/u',
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        color: AppColors.info,
                                        size: 18,
                                      ),
                                      onPressed: () => _editarPrecioItem(i),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: AppColors.danger,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          setState(() => _carrito.removeAt(i)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  if (_mesaSeleccionadaNombre != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: _guardarCambiosEnMesa,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Guardar Mesa'),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '\$${totalCarrito.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.tealDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _carrito.isEmpty
                        ? null
                        : _verificarYProcesarCobro,
                    icon: const Icon(Icons.point_of_sale_rounded, size: 20),
                    label: const Text(
                      'Cobrar Venta',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
