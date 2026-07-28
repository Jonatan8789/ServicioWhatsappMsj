import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'reserva_cancha_model.dart';

class CanchasPage extends StatefulWidget {
  const CanchasPage({super.key});

  @override
  State<CanchasPage> createState() => _CanchasPageState();
}

class _CanchasPageState extends State<CanchasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  // Elementos Visuales de Equipamiento
  bool _alquilaPaleta = false;
  bool _alquilaPelotas = false;

  double _precioSocioRef = 4500.0;
  double _precioExternoRef = 6000.0;
  double _precioPaletaAnexo = 1500.0;
  double _precioPelotasAnexo = 1000.0;

  // Lógica Horaria e Iluminación Nocturna
  int _horaApertura = 8;
  int _horaCierre = 23;
  int _duracionSeleccionada = 1;
  int _horaInicioCarga = 20;
  double _plusLuzAnexo = 1500.0;
  int? _horaInicioSeleccionada;

  bool _cargandoTarifas = true;

  final _clienteController = TextEditingController();
  DateTime _fechaSeleccionada = DateTime.now();

  String? _canchaSel;
  String _tipoCliente = 'Socio';
  String? _socioIdSeleccionado;
  String _metodoPagoSel = 'Cuenta Corriente';

  String _busquedaSocio = "";
  Map<String, dynamic>? _socioElegido;

  @override
  void initState() {
    super.initState();
    _cargarTarifarioGlobal();
  }

  @override
  void dispose() {
    _clienteController.dispose();
    super.dispose();
  }

  Future<void> _cargarTarifarioGlobal() async {
    setState(() => _cargandoTarifas = true);
    try {
      final docAjustes = await _firestore
          .collection('configuraciones_paddle')
          .doc('ajustes_globales')
          .get();

      if (docAjustes.exists && docAjustes.data() != null) {
        final data = docAjustes.data()!;
        setState(() {
          _precioSocioRef =
              (data['precio_base_cancha'] as num?)?.toDouble() ?? 4500.0;
          _precioExternoRef =
              (data['precio_base_externo'] as num?)?.toDouble() ?? 6000.0;
          _precioPaletaAnexo =
              (data['precio_alquiler_paleta'] as num?)?.toDouble() ?? 1500.0;
          _precioPelotasAnexo =
              (data['precio_alquiler_pelotas'] as num?)?.toDouble() ?? 1000.0;
          _horaInicioCarga = (data['hora_inicio_luz'] as num?)?.toInt() ?? 20;
          _plusLuzAnexo =
              (data['precio_adicional_luz'] as num?)?.toDouble() ?? 1500.0;

          _horaApertura = (data['hora_apertura'] as num?)?.toInt() ?? 8;
          _horaCierre = (data['hora_cierre'] as num?)?.toInt() ?? 23;
        });
      }
    } catch (e) {
      print("Error cargando configuración comercial: $e");
    } finally {
      setState(() => _cargandoTarifas = false);
    }
  }

  double get precioBaseActual {
    return _tipoCliente == 'Socio' ? _precioSocioRef : _precioExternoRef;
  }

  double get totalReservaEnTiempoReal {
    if (_horaInicioSeleccionada == null) return 0.0;

    double total = 0.0;
    for (
      int h = _horaInicioSeleccionada!;
      h < _horaInicioSeleccionada! + _duracionSeleccionada;
      h++
    ) {
      total += precioBaseActual;
      if (h >= _horaInicioCarga) {
        total += _plusLuzAnexo;
      }
      if (_alquilaPaleta) total += _precioPaletaAnexo;
      if (_alquilaPelotas) total += _precioPelotasAnexo;
    }
    return total;
  }

  Future<void> _crearVentaPendienteParaCaja({
    required String socioId,
    required String nombreSocio,
    required String numeroCancha,
    required String horaTurno,
    required double precioCancha,
    List<Map<String, dynamic>> equipamientoAlquilado = const [],
  }) async {
    try {
      List<Map<String, dynamic>> itemsCobro = [
        {
          'id': 'servicio_cancha_paddle',
          'nombre': 'Alquiler $numeroCancha ($horaTurno)',
          'precio': precioCancha,
          'cantidad': 1,
          'es_producto_fisico': false,
        },
      ];

      for (var equipo in equipamientoAlquilado) {
        itemsCobro.add({
          'id': equipo['id'],
          'nombre': equipo['nombre'],
          'precio': equipo['precio'],
          'cantidad': equipo['cantidad'],
          'es_producto_fisico': equipo['es_producto_fisico'],
        });
      }

      await _firestore.collection('ventas_pendientes').add({
        'socio_id': socioId,
        'nombre_socio': nombreSocio,
        'origen': 'Reserva $numeroCancha - $horaTurno',
        'fecha_creacion': FieldValue.serverTimestamp(),
        'estado': 'Pendiente',
        'items': itemsCobro,
      });
    } catch (e) {
      print('Error al enviar standby a caja: $e');
    }
  }

  /// 📲 Notificación por WhatsApp al Socio
  Future<void> _enviarNotificacionReservaWhatsApp({
    required String telefono,
    required String nombreSocio,
    required String cancha,
    required DateTime fecha,
    required int horaInicio,
    required int duracion,
  }) async {
    final telefonoLimpio = telefono.replaceAll(RegExp(r'\D'), '');
    if (telefonoLimpio.isEmpty) return;

    final String fechaFormateada =
        "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
    final String horaInicioStr = "${horaInicio.toString().padLeft(2, '0')}:00";
    final String horaFinStr =
        "${(horaInicio + duracion).toString().padLeft(2, '0')}:00";

    final mensaje =
        '''
🎾 *¡RESERVA CONFIRMADA - OQUA CLUB DEPORTIVO!*

Hola *$nombreSocio*, confirmamos tu turno de pádel:

📍 *Cancha:* $cancha
📅 *Fecha:* $fechaFormateada
⏰ *Horario:* De $horaInicioStr a $horaFinStr hs ($duracion hr/s)

¡Te esperamos en el club! Por favor, recordá avisar con anticipación en caso de requerir cancelación.
''';

    try {
      await http.post(
        // ✅ Corrección a aplicar:
        Uri.parse('https://servicio-whatsapp-oqua.onrender.com/send-whatsapp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': telefonoLimpio, 'message': mensaje}),
      );
    } catch (e) {
      print('⚠️ No se pudo enviar la notificación de WhatsApp: $e');
    }
  }

  Future<void> _registrarReserva() async {
    if (!_formKey.currentState!.validate() ||
        _canchaSel == null ||
        _horaInicioSeleccionada == null) {
      _snack(
        'Completar todos los campos (selecciona un horario en la grilla).',
        Colors.orange,
      );
      return;
    }

    if (_tipoCliente == 'Socio' && _socioIdSeleccionado == null) {
      _snack('Selecciona un socio válido de la lista buscador.', Colors.orange);
      return;
    }

    if (_horaInicioSeleccionada! + _duracionSeleccionada > _horaCierre) {
      _snack(
        'La duración seleccionada excede el horario de cierre del complejo.',
        Colors.red,
      );
      return;
    }

    final fechaIdStr =
        "${_fechaSeleccionada.year}-${_fechaSeleccionada.month}-${_fechaSeleccionada.day}";

    final reservaId =
        "${fechaIdStr}_${_canchaSel!.replaceAll(' ', '')}_${_horaInicioSeleccionada}hs_duracion${_duracionSeleccionada}h";

    final String nombreFinal = _tipoCliente == 'Socio'
        ? ('${_socioElegido?['nombre'] ?? ''} ${_socioElegido?['apellido'] ?? ''}'
              .trim())
        : _clienteController.text.trim();

    double costoCanchaTotal = 0.0;
    double costoExtrasTotal = 0.0;

    for (
      int h = _horaInicioSeleccionada!;
      h < _horaInicioSeleccionada! + _duracionSeleccionada;
      h++
    ) {
      costoCanchaTotal += precioBaseActual;
      if (h >= _horaInicioCarga) {
        costoCanchaTotal += _plusLuzAnexo;
      }
      if (_alquilaPaleta) costoExtrasTotal += _precioPaletaAnexo;
      if (_alquilaPelotas) costoExtrasTotal += _precioPelotasAnexo;
    }

    final double precioFinalCalculado = costoCanchaTotal + costoExtrasTotal;

    final nuevaReserva = ReservaCanchaModel(
      id: reservaId,
      cancha: _canchaSel!,
      nombreCliente: nombreFinal,
      socioId: _tipoCliente == 'Socio' ? _socioIdSeleccionado : null,
      fecha: _fechaSeleccionada,
      horaInicio: _horaInicioSeleccionada!,
      duracionHoras: _duracionSeleccionada,
      precio: precioFinalCalculado,
      metodoPago: _metodoPagoSel,
    );

    try {
      final snapshotCanchas = await _firestore
          .collection('reservas_canchas')
          .get();
      for (var doc in snapshotCanchas.docs) {
        final r = ReservaCanchaModel.fromFirestore(doc.id, doc.data());
        final String fId = "${r.fecha.year}-${r.fecha.month}-${r.fecha.day}";

        if (fId == fechaIdStr && r.cancha == _canchaSel!) {
          int rInicio = r.horaInicio;
          int rFin = rInicio + r.duracionHoras;

          for (
            int h = _horaInicioSeleccionada!;
            h < _horaInicioSeleccionada! + _duracionSeleccionada;
            h++
          ) {
            if (h >= rInicio && h < rFin) {
              _snack(
                'Solapamiento detectado. El bloque ya se encuentra reservado.',
                Colors.red,
              );
              return;
            }
          }
        }
      }

      await _firestore
          .collection('reservas_canchas')
          .doc(reservaId)
          .set(nuevaReserva.toFirestore());

      // 📲 DISPARO AUTOMÁTICO DE WHATSAPP
      final String? telefonoSocio =
          (_tipoCliente == 'Socio' && _socioElegido != null)
          ? (_socioElegido!['telefono'] as String?)
          : null;
      if (telefonoSocio != null && telefonoSocio.isNotEmpty) {
        _enviarNotificacionReservaWhatsApp(
          telefono: telefonoSocio,
          nombreSocio: nombreFinal,
          cancha: _canchaSel!,
          fecha: _fechaSeleccionada,
          horaInicio: _horaInicioSeleccionada!,
          duracion: _duracionSeleccionada,
        );
      }

      if (_tipoCliente == 'Socio' && _socioIdSeleccionado != null) {
        List<Map<String, dynamic>> extras = [];
        if (_alquilaPaleta) {
          extras.add({
            'id': 'prod_alquiler_paleta',
            'nombre': 'Alquiler Paleta (x$_duracionSeleccionada hrs)',
            'precio': _precioPaletaAnexo * _duracionSeleccionada,
            'cantidad': 1,
            'es_producto_fisico': false,
          });
        }
        if (_alquilaPelotas) {
          extras.add({
            'id': 'prod_tubo_pelotas',
            'nombre': 'Alquiler Tubo de Pelotas (x$_duracionSeleccionada hrs)',
            'precio': _precioPelotasAnexo * _duracionSeleccionada,
            'cantidad': 1,
            'es_producto_fisico': false,
          });
        }

        final String stringBloqueParaCaja =
            "${_horaInicioSeleccionada!.toString().padLeft(2, '0')}:00 hs por $_duracionSeleccionada Hora(s)";
        await _crearVentaPendienteParaCaja(
          socioId: _socioIdSeleccionado!,
          nombreSocio: nombreFinal,
          numeroCancha: _canchaSel!,
          horaTurno: stringBloqueParaCaja,
          precioCancha: costoCanchaTotal,
          equipamientoAlquilado: extras,
        );
      }

      _limpiarFormulario();
      if (mounted) {
        _snack('¡Turno registrado y notificación enviada!', Colors.green);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', Colors.red);
    }
  }

  void _mostrarConsolaTurnoOcupado(ReservaCanchaModel reserva) {
    final senaCtrl = TextEditingController();
    String medioSena = 'Efectivo ARS';

    final Map<String, dynamic> rawData = reserva.toFirestore();
    double senaPrevia = 0.0;
    if (rawData.containsKey('seña_abonada')) {
      senaPrevia = (rawData['seña_abonada'] as num).toDouble();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Administrar: ${reserva.nombreCliente}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cancha: ${reserva.cancha} | Hora: ${reserva.horaInicio}:00 hs',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Valor Restante por Cobrar: \$${reserva.precio.toStringAsFixed(0)} ARS',
                style: const TextStyle(color: Colors.grey),
              ),
              if (senaPrevia > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    'Seña ya entregada: \$$senaPrevia (${rawData['detalle_seña'] ?? ''})',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              const Divider(height: 24),
              const Text(
                'Registrar Entrega de Seña:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: senaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monto Seña',
                        border: OutlineInputBorder(),
                        prefixText: '\$ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: medioSena,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Efectivo ARS',
                          child: Text('Efectivo'),
                        ),
                        DropdownMenuItem(
                          value: 'Mercado Pago',
                          child: Text('Mercado Pago'),
                        ),
                        DropdownMenuItem(value: 'MODO', child: Text('MODO')),
                      ],
                      onChanged: (v) => medioSena = v!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                await _firestore
                    .collection('reservas_canchas')
                    .doc(reserva.id)
                    .delete();
                _snack(
                  '🔓 Cancha liberada. El turno vuelve a estar disponible.',
                  Colors.green,
                );
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('Liberar / Cancelar Turno'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
              ),
              onPressed: () async {
                final montoSena = double.tryParse(senaCtrl.text.trim()) ?? 0.0;
                if (montoSena <= 0) return;

                Navigator.pop(context);

                await _firestore
                    .collection('reservas_canchas')
                    .doc(reserva.id)
                    .update({
                      'precio': reserva.precio - montoSena,
                      'seña_abonada': senaPrevia + montoSena,
                      'detalle_seña': 'Señado con $medioSena',
                    });

                final cajaQuery = await _firestore
                    .collection('control_cajas')
                    .where('usuario', isEqualTo: 'Administrador Central')
                    .where('estado', isEqualTo: 'Abierta')
                    .limit(1)
                    .get();

                if (cajaQuery.docs.isNotEmpty) {
                  String campo = medioSena == 'Efectivo ARS'
                      ? 'totalEfectivoARS'
                      : (medioSena == 'Mercado Pago'
                            ? 'totalMercadoPago'
                            : 'totalModo');
                  await _firestore
                      .collection('control_cajas')
                      .doc(cajaQuery.docs.first.id)
                      .update({campo: FieldValue.increment(montoSena)});
                }

                _snack(
                  '💰 Seña de \$$montoSena asentada en caja y descontada del total.',
                  Colors.green,
                );
              },
              child: const Text(
                'Asentar Seña',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _anularReservasHistoricasViejas() async {
    final DateTime hoy = DateTime.now();
    final DateTime umbralSaneamiento = DateTime(hoy.year, hoy.month, hoy.day);

    try {
      final snapshot = await _firestore.collection('reservas_canchas').get();
      WriteBatch batch = _firestore.batch();
      int contadorBorrados = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['fecha'] != null) {
          final DateTime fechaReserva = (data['fecha'] as Timestamp).toDate();
          if (fechaReserva.isBefore(umbralSaneamiento)) {
            batch.delete(doc.reference);
            contadorBorrados++;
          }
        }
      }

      if (contadorBorrados > 0) {
        await batch.commit();
        _snack(
          '🧹 Se purgaron $contadorBorrados turnos obsoletos del historial.',
          Colors.teal,
        );
      } else {
        _snack(
          '✅ El historial de reservas se encuentra limpio y al día.',
          Colors.blue,
        );
      }
    } catch (e) {
      _snack('❌ Error al depurar historial: $e', Colors.red);
    }
  }

  void _limpiarFormulario() {
    setState(() {
      _clienteController.clear();
      _canchaSel = null;
      _horaInicioSeleccionada = null;
      _socioIdSeleccionado = null;
      _socioElegido = null;
      _busquedaSocio = "";
      _alquilaPaleta = false;
      _alquilaPelotas = false;
      _duracionSeleccionada = 1;
    });
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
  }

  List<Widget> _generarBloquesHorarios(
    String canchaNombre,
    Map<String, ReservaCanchaModel> mapaReservas,
    String fechaIdStr,
  ) {
    List<Widget> celdas = [];

    for (int hora = _horaApertura; hora < _horaCierre; hora++) {
      final String bloqueStr = "${hora.toString().padLeft(2, '0')}:00 hs";

      double precioBloqueFinal = precioBaseActual;
      if (hora >= _horaInicioCarga) {
        precioBloqueFinal += _plusLuzAnexo;
      }

      bool estaOcupado = false;
      ReservaCanchaModel? reservaActiva;

      mapaReservas.forEach((id, r) {
        final String fId = "${r.fecha.year}-${r.fecha.month}-${r.fecha.day}";
        if (fId == fechaIdStr && r.cancha == canchaNombre) {
          int inicio = r.horaInicio;
          int fin = inicio + r.duracionHoras;
          if (hora >= inicio && hora < fin) {
            estaOcupado = true;
            reservaActiva = r;
          }
        }
      });

      final bool esElSeleccionadoActualmente =
          _canchaSel == canchaNombre && _horaInicioSeleccionada == hora;

      String rotuloCliente = 'Disponible';
      if (estaOcupado && reservaActiva != null) {
        final rawMap = reservaActiva!.toFirestore();
        if (rawMap.containsKey('seña_abonada') &&
            (rawMap['seña_abonada'] as num) > 0) {
          rotuloCliente = '${reservaActiva!.nombreCliente} (💰 SEÑADO)';
        } else {
          rotuloCliente = reservaActiva!.nombreCliente;
        }
      } else if (esElSeleccionadoActualmente) {
        rotuloCliente = 'Seleccionado';
      }

      celdas.add(
        InkWell(
          onTap: () {
            if (!estaOcupado) {
              setState(() {
                _canchaSel = canchaNombre;
                _horaInicioSeleccionada = hora;
              });
            } else {
              if (reservaActiva != null)
                _mostrarConsolaTurnoOcupado(reservaActiva!);
            }
          },
          child: Container(
            width: 180,
            height: 85,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: estaOcupado
                  ? const Color(0xFFFFE2E2)
                  : (esElSeleccionadoActualmente
                        ? Colors.indigo.shade50
                        : const Color(0xFFF0FDF4)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: estaOcupado
                    ? Colors.red.shade200
                    : (esElSeleccionadoActualmente
                          ? Colors.indigo
                          : Colors.green.shade200),
                width: esElSeleccionadoActualmente ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      bloqueStr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: estaOcupado
                            ? Colors.red.shade900
                            : Colors.green.shade900,
                      ),
                    ),
                    if (hora >= _horaInicioCarga && !estaOcupado)
                      const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 14,
                        color: Colors.orange,
                      ),
                  ],
                ),
                Text(
                  rotuloCliente,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  estaOcupado
                      ? 'Ocupado'
                      : '\$${precioBloqueFinal.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: estaOcupado
                        ? Colors.red.shade700
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return celdas;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoTarifas) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.indigo),
              SizedBox(height: 16),
              Text('Sincronizando grilla y tarifario comercial...'),
            ],
          ),
        ),
      );
    }

    final fechaIdStr =
        "${_fechaSeleccionada.year}-${_fechaSeleccionada.month}-${_fechaSeleccionada.day}";

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nueva Reserva de Paddle',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                          initialValue: _tipoCliente,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de Cliente',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Socio',
                              child: Text('Socio del Club'),
                            ),
                            DropdownMenuItem(
                              value: 'Externo',
                              child: Text('Externo (No Socio)'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _tipoCliente = val;
                                _metodoPagoSel = val == 'Socio'
                                    ? 'Cuenta Corriente'
                                    : 'Efectivo';
                                _socioIdSeleccionado = null;
                                _socioElegido = null;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 20),
                        if (_tipoCliente == 'Socio') ...[
                          if (_socioElegido == null) ...[
                            TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Buscar Socio...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) => setState(
                                () => _busquedaSocio = v.toLowerCase(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_busquedaSocio.length >= 3)
                              Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 150,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.white,
                                ),
                                child: StreamBuilder<QuerySnapshot>(
                                  stream: _firestore
                                      .collection('socios')
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData)
                                      return const Center(
                                        child: LinearProgressIndicator(),
                                      );
                                    final filtrados = snapshot.data!.docs.where(
                                      (doc) {
                                        final d =
                                            doc.data() as Map<String, dynamic>;
                                        final nombre = (d['nombre'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        final apellido = (d['apellido'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        final dni = (d['dni'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        return nombre.contains(
                                              _busquedaSocio,
                                            ) ||
                                            apellido.contains(_busquedaSocio) ||
                                            dni.contains(_busquedaSocio);
                                      },
                                    ).toList();

                                    if (filtrados.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: Text(
                                          'No hay coincidencias.',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    }

                                    return ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: filtrados.length,
                                      itemBuilder: (context, idx) {
                                        final doc = filtrados[idx];
                                        final d =
                                            doc.data() as Map<String, dynamic>;
                                        return ListTile(
                                          title: Text(
                                            '${d['nombre'] ?? ''} ${d['apellido'] ?? ''}'
                                                .trim(),
                                          ),
                                          subtitle: Text(
                                            'DNI: ${d['dni'] ?? 'S/D'}',
                                          ),
                                          onTap: () => setState(() {
                                            _socioElegido = d;
                                            _socioIdSeleccionado = doc.id;
                                          }),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                          ] else ...[
                            Card(
                              color: const Color(0xFFEFF6FF),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.check_circle,
                                  color: Colors.blue,
                                ),
                                title: Text(
                                  '${_socioElegido!['nombre'] ?? ''} ${_socioElegido!['apellido'] ?? ''}'
                                      .trim(),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      setState(() => _socioElegido = null),
                                ),
                              ),
                            ),
                          ],
                        ] else ...[
                          TextFormField(
                            controller: _clienteController,
                            decoration: const InputDecoration(
                              labelText: 'Responsable Externo',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Ingresa el nombre'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 20),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Cancha y Horario Seleccionado',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.sports_tennis),
                          ),
                          child: Text(
                            _canchaSel != null &&
                                    _horaInicioSeleccionada != null
                                ? '$_canchaSel - ${_horaInicioSeleccionada!.toString().padLeft(2, '0')}:00 hs'
                                : 'Toca una celda libre en la grilla',
                            style: TextStyle(
                              color: _canchaSel != null
                                  ? Colors.black
                                  : Colors.grey,
                              fontWeight: _canchaSel != null
                                  ? FontWeight.bold
                                  : Alignment.topLeft == null
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<int>(
                          initialValue: _duracionSeleccionada,
                          decoration: const InputDecoration(
                            labelText: 'Duración de la Reserva',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.schedule_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 Hora')),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('2 Horas (Turno Doble)'),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _duracionSeleccionada = val ?? 1),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          initialValue: _metodoPagoSel,
                          decoration: const InputDecoration(
                            labelText: 'Método de Pago',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            if (_tipoCliente == 'Socio')
                              const DropdownMenuItem(
                                value: 'Cuenta Corriente',
                                child: Text('Cuenta Corriente 📋'),
                              ),
                            const DropdownMenuItem(
                              value: 'Efectivo',
                              child: Text('Efectivo ARS'),
                            ),
                            const DropdownMenuItem(
                              value: 'Mercado Pago',
                              child: Text('Mercado Pago'),
                            ),
                          ],
                          onChanged: (val) => setState(
                            () => _metodoPagoSel = val ?? 'Efectivo',
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Equipamiento Adicional:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        CheckboxListTile(
                          title: Text(
                            'Alquiler de Paleta (+\$${_precioPaletaAnexo.toStringAsFixed(0)} /hr)',
                          ),
                          value: _alquilaPaleta,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (val) =>
                              setState(() => _alquilaPaleta = val ?? false),
                        ),
                        CheckboxListTile(
                          title: Text(
                            'Alquiler Tubo de Pelotas (+\$${_precioPelotasAnexo.toStringAsFixed(0)} /hr)',
                          ),
                          value: _alquilaPelotas,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (val) =>
                              setState(() => _alquilaPelotas = val ?? false),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Precio Cancha (Base):',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '\$${(precioBaseActual * _duracionSeleccionada).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (_horaInicioSeleccionada != null &&
                                  _horaInicioSeleccionada! >=
                                      _horaInicioCarga) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Plus Nocturno (Luz):',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '+\$${(_plusLuzAnexo * _duracionSeleccionada).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (_alquilaPaleta || _alquilaPelotas) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Equipamiento Adicional:',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '+\$${((_alquilaPaleta ? _precioPaletaAnexo : 0) + (_alquilaPelotas ? _precioPelotasAnexo : 0) * _duracionSeleccionada).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Divider(height: 1),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'TOTAL A COBRAR:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    '\$${totalReservaEnTiempoReal.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _registrarReserva,
                          child: const Text(
                            'Confirmar Turno & Enviar a Caja',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Disponibilidad de Canchas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Purgar Reservas de Días Anteriores',
                              icon: const Icon(
                                Icons.cleaning_services_rounded,
                                color: Colors.teal,
                              ),
                              onPressed: _anularReservasHistoricasViejas,
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _fechaSeleccionada,
                                  firstDate: DateTime.now().subtract(
                                    const Duration(days: 7),
                                  ),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 30),
                                  ),
                                );
                                if (picked != null)
                                  setState(() => _fechaSeleccionada = picked);
                              },
                              icon: const Icon(Icons.calendar_month),
                              label: Text(
                                '${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: StreamBuilder<DocumentSnapshot>(
                        stream: _firestore
                            .collection('configuracion_paddle')
                            .doc('canchas')
                            .snapshots(),
                        builder: (context, configSnapshot) {
                          List<String> canchasDinamicas = [
                            "Cancha 1 Cristal",
                            "Cancha 2 Cristal",
                            "Cancha 3 Muro",
                          ];

                          if (configSnapshot.hasData &&
                              configSnapshot.data!.exists) {
                            final configData =
                                configSnapshot.data!.data()
                                    as Map<String, dynamic>?;
                            if (configData != null &&
                                configData['lista'] != null) {
                              canchasDinamicas = List<String>.from(
                                configData['lista'],
                              );
                            }
                          }

                          return StreamBuilder<QuerySnapshot>(
                            stream: _firestore
                                .collection('reservas_canchas')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData)
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );

                              final mapaReservas = {
                                for (var doc in snapshot.data!.docs)
                                  doc.id: ReservaCanchaModel.fromFirestore(
                                    doc.id,
                                    doc.data() as Map<String, dynamic>,
                                  ),
                              };

                              return ListView.builder(
                                itemCount: canchasDinamicas.length,
                                itemBuilder: (context, cIdx) {
                                  final canchaNombre = canchasDinamicas[cIdx];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: ExpansionTile(
                                      initiallyExpanded: cIdx == 0,
                                      title: Text(
                                        canchaNombre,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      children: [
                                        Container(
                                          color: Colors.white,
                                          padding: const EdgeInsets.all(16),
                                          child: Wrap(
                                            spacing: 12,
                                            runSpacing: 12,
                                            children: _generarBloquesHorarios(
                                              canchaNombre,
                                              mapaReservas,
                                              fechaIdStr,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
          ],
        ),
      ),
    );
  }
}
