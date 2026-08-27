import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cloud_functions;
import 'package:http/http.dart' as http;
import 'producto_buffet_model.dart';
import '../tarifas/tarifa_model.dart';

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
  String? _socioSeleccionadoId;
  String _busquedaSocioPOS = "";
  Map<String, dynamic>? _socioSeleccionadoPOS;

  List<DocumentSnapshot> _reservasPendientesDelSocio = [];
  bool _buscandoReservas = false;

  String? _mesaSeleccionadaNombre;
  final String _usuarioOperador = "Administrador Central";

  double get totalCarrito {
    return _carrito.fold(
      0,
      (sum, item) => sum + (item['precio'] * item['cantidad']),
    );
  }

  // ✏️ EDICIÓN MANUAL DE PRECIO
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
              setState(() {
                _carrito[index]['precio'] = nuevoMonto;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  // 🔍 BUSCADOR INTELIGENTE: BÚSQUEDA DE RESERVAS PENDIENTES (PADDLE / TURNOS)
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

  // 🔍 BUSCADOR INTELIGENTE: VERIFICACIÓN DE MATRÍCULA ANUAL
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

  // 🔍 BUSCADOR INTELIGENTE: VERIFICACIÓN Y CARGA DE CUOTA DEL MES
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
    final String mesActualClave =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}";

    final cuotasPagas = await _firestore
        .collection('socios')
        .doc(socioId)
        .collection('cuotas_pagas')
        .doc(mesActualClave)
        .get();

    if (cuotasPagas.exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ℹ️ El socio se encuentra al día con la cuota de este mes.',
            ),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }
      return;
    }

    final tarifa = await _obtenerTarifaVigente(
      deporte: socioData['deporte'] ?? 'Socio Natatorio',
      frecuencia: socioData['frecuencia'] ?? 'Pase Libre',
    );

    double precioRegular = tarifa?.precioRegular ?? 15000.0;
    double precioEfectivo = tarifa?.precioEfectivo ?? precioRegular;

    // Aplicar porcentaje escolar si corresponde
    if (socioData['esEstudianteEscuela'] == true) {
      final double dto =
          (socioData['descuentoEscolarPorcentaje'] as num?)?.toDouble() ?? 0.0;
      if (dto > 0) {
        precioRegular -= (precioRegular * (dto / 100));
        precioEfectivo -= (precioEfectivo * (dto / 100));
      }
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cuota Social Pendiente'),
          content: Text(
            'Generar cobro para la cuota $mesActualClave.\n\n• Precio Regular: \$${precioRegular.toStringAsFixed(0)} ARS\n• Descuento Efectivo: \$${precioEfectivo.toStringAsFixed(0)} ARS',
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
                    'id': 'cuota_$mesActualClave',
                    'nombre': 'Cuota Social $mesActualClave',
                    'precio': precioRegular,
                    'precioRegularAuto': precioRegular,
                    'precioEfectivoAuto': precioEfectivo,
                    'cantidad': 1,
                    'es_producto_fisico': false,
                    'esCuotaSocial': true,
                    'mesPeriodo': mesActualClave,
                  });
                });
              },
              child: const Text(
                'Agregar Cuota al Ticket',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
  }

  // 🗺️ CONTROL DE MESAS Y COMANDAS EN VIVO
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

  // 🔍 WIDGET: BUSCADOR DE SOCIOS CON AUTOCOMPLETADO
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
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('socios').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        final query = _busquedaSocioPOS.toLowerCase().trim();

        final docs = snapshot.data!.docs.where((d) {
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
        );
      },
    );
  }

  // 🚪 COBRO Y IMPACTO
  void _mostrarDialogoCobro() {
    if (_carrito.isEmpty) return;
    String medioPagoSeleccionado = 'Efectivo ARS';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Procesar Cobro'),
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
                  });
                },
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

  Future<void> _procesarVentaFirestore(String medio) async {
    final cajaQuery = await _firestore
        .collection('control_cajas')
        .where('usuario', isEqualTo: _usuarioOperador)
        .where('estado', isEqualTo: 'Abierta')
        .limit(1)
        .get();

    if (cajaQuery.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Abrí la caja antes de procesar cobros.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final docCajaId = cajaQuery.docs.first.id;
    WriteBatch batch = _firestore.batch();

    for (var item in _carrito) {
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

      if (item['origen_pendiente_id'] != null) {
        DocumentReference resRef = _firestore
            .collection('ventas_pendientes')
            .doc(item['origen_pendiente_id']);
        batch.update(resRef, {
          'estado': 'Cobrado',
          'fechaCobro': DateTime.now(),
        });
      }
    }

    DocumentReference ventaRef = _firestore.collection('ventas_buffet').doc();
    batch.set(ventaRef, {
      'items': _carrito,
      'total': totalCarrito,
      'medio_pago': medio,
      'fecha': DateTime.now(),
      'socio_id': _socioSeleccionadoId,
      'origen_salón': _mesaSeleccionadaNombre ?? 'Mostrador Directo',
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
        'detalle': 'Consumo asignado a Cuenta Corriente',
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

    setState(() {
      _carrito.clear();
      _socioSeleccionadoId = null;
      _socioSeleccionadoPOS = null;
      _mesaSeleccionadaNombre = null;
      _reservasPendientesDelSocio = [];
    });

    if (mounted) {
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
                  Text(
                    _mesaSeleccionadaNombre == null
                        ? 'Terminal POS - Venta Directa'
                        : 'Mesa Activa: $_mesaSeleccionadaNombre',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
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

                  // 🎾 RESERVAS DE CANCHAS/PADDLE ENCONTRADAS PARA EL SOCIO
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
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        final docs = snapshot.data!.docs;

                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final p = ProductoBuffetModel.fromFirestore(
                              docs[i],
                            );
                            return InkWell(
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
                              child: Card(
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        p.nombre,
                                        textAlign: TextAlign.center,
                                      ),
                                      Text('\$${p.precio.toStringAsFixed(0)}'),
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
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen de Ticket',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _carrito.length,
                      itemBuilder: (context, i) {
                        final item = _carrito[i];
                        return ListTile(
                          title: Text(item['nombre']),
                          subtitle: Text('Monto: \$${item['precio']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _editarPrecioItem(i),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
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
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        minimumSize: const Size.fromHeight(40),
                      ),
                      onPressed: _guardarCambiosEnMesa,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        'Guardar Mesa',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'TOTAL: \$${totalCarrito.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _carrito.isEmpty ? null : _mostrarDialogoCobro,
                    child: const Text(
                      'Cobrar Venta',
                      style: TextStyle(color: Colors.white),
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
