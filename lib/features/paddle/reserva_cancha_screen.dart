import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'reserva_cancha_model.dart';

class ReservaCanchaScreen extends StatefulWidget {
  const ReservaCanchaScreen({super.key});

  @override
  State<ReservaCanchaScreen> createState() => _ReservaCanchaScreenState();
}

class _ReservaCanchaScreenState extends State<ReservaCanchaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _fechaSeleccionada = DateTime.now();
  String? _canchaSeleccionada;
  int? _horaInicioSeleccionada;
  int _duracionHoras = 1;

  bool _alquilaPaleta = false;
  bool _alquilaPelotas = false;
  bool _cargando = false;

  double _precioBaseSocio = 4500.0;
  double _precioPaletaAnexo = 1500.0;
  double _precioPelotasAnexo = 1000.0;
  int _horaInicioCargaLuz = 20;
  double _plusLuzAnexo = 1500.0;
  int _horaApertura = 8;
  int _horaCierre = 23;

  List<String> _canchasActivas = [];
  Map<String, dynamic>? _datosSocio;

  @override
  void initState() {
    super.initState();
    _cargarAjustesGlobales();
  }

  Future<void> _cargarAjustesGlobales() async {
    setState(() => _cargando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docSocio = await _firestore
            .collection('socios')
            .doc(user.uid)
            .get();
        if (docSocio.exists) _datosSocio = docSocio.data();
      }

      final docAjustes = await _firestore
          .collection('configuraciones_paddle')
          .doc('ajustes_globales')
          .get();
      if (docAjustes.exists && docAjustes.data() != null) {
        final d = docAjustes.data()!;
        _precioBaseSocio =
            (d['precio_base_cancha'] as num?)?.toDouble() ?? 4500.0;
        _precioPaletaAnexo =
            (d['precio_alquiler_paleta'] as num?)?.toDouble() ?? 1500.0;
        _precioPelotasAnexo =
            (d['precio_alquiler_pelotas'] as num?)?.toDouble() ?? 1000.0;
        _horaInicioCargaLuz = (d['hora_inicio_luz'] as num?)?.toInt() ?? 20;
        _plusLuzAnexo =
            (d['precio_adicional_luz'] as num?)?.toDouble() ?? 1500.0;
        _horaApertura = (d['hora_apertura'] as num?)?.toInt() ?? 8;
        _horaCierre = (d['hora_cierre'] as num?)?.toInt() ?? 23;
      }

      final docCanchas = await _firestore
          .collection('configuracion_paddle')
          .doc('canchas')
          .get();
      if (docCanchas.exists && docCanchas.data()?['lista'] != null) {
        _canchasActivas = List<String>.from(docCanchas.data()!['lista']);
      } else {
        _canchasActivas = [
          "Cancha 1 Cristal",
          "Cancha 2 Cristal",
          "Cancha 3 Muro",
        ];
      }

      if (_canchasActivas.isNotEmpty) {
        _canchaSeleccionada = _canchasActivas.first;
      }
    } catch (e) {
      _snack('Error al cargar configuración: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  double get totalCalculado {
    if (_horaInicioSeleccionada == null) return 0.0;
    double total = 0.0;
    for (
      int h = _horaInicioSeleccionada!;
      h < _horaInicioSeleccionada! + _duracionHoras;
      h++
    ) {
      total += _precioBaseSocio;
      if (h >= _horaInicioCargaLuz) total += _plusLuzAnexo;
      if (_alquilaPaleta) total += _precioPaletaAnexo;
      if (_alquilaPelotas) total += _precioPelotasAnexo;
    }
    return total;
  }

  Future<void> _confirmarReserva() async {
    if (_canchaSeleccionada == null || _horaInicioSeleccionada == null) {
      _snack('Seleccioná cancha y horario.', Colors.orange);
      return;
    }

    setState(() => _cargando = true);

    final fechaIdStr =
        "${_fechaSeleccionada.year}-${_fechaSeleccionada.month}-${_fechaSeleccionada.day}";
    final canchaLimpia = _canchaSeleccionada!.replaceAll(' ', '');
    final reservaId =
        "${fechaIdStr}_${canchaLimpia}_${_horaInicioSeleccionada}hs_duracion${_duracionHoras}h";

    final String nombreSocio = _datosSocio != null
        ? '${_datosSocio!['nombre'] ?? ''} ${_datosSocio!['apellido'] ?? ''}'
              .trim()
        : 'Socio Mobile';

    final nuevaReserva = ReservaCanchaModel(
      id: reservaId,
      cancha: _canchaSeleccionada!,
      nombreCliente: nombreSocio,
      socioId: FirebaseAuth.instance.currentUser?.uid,
      fecha: _fechaSeleccionada,
      horaInicio: _horaInicioSeleccionada!,
      duracionHoras: _duracionHoras,
      precio: totalCalculado,
      metodoPago: 'Cuenta Corriente',
    );

    try {
      final snapshot = await _firestore.collection('reservas_canchas').get();
      for (var doc in snapshot.docs) {
        final r = ReservaCanchaModel.fromFirestore(doc.id, doc.data());
        final fId = "${r.fecha.year}-${r.fecha.month}-${r.fecha.day}";
        if (fId == fechaIdStr && r.cancha == _canchaSeleccionada!) {
          int rInicio = r.horaInicio;
          int rFin = rInicio + r.duracionHoras;
          for (
            int h = _horaInicioSeleccionada!;
            h < _horaInicioSeleccionada! + _duracionHoras;
            h++
          ) {
            if (h >= rInicio && h < rFin) {
              _snack('¡El horario ya fue reservado!', Colors.red);
              return;
            }
          }
        }
      }

      await _firestore
          .collection('reservas_canchas')
          .doc(reservaId)
          .set(nuevaReserva.toFirestore());

      if (FirebaseAuth.instance.currentUser != null) {
        await _firestore.collection('ventas_pendientes').add({
          'socio_id': FirebaseAuth.instance.currentUser!.uid,
          'nombre_socio': nombreSocio,
          'origen':
              'Reserva App - $_canchaSeleccionada ($_horaInicioSeleccionada:00 hs)',
          'fecha_creacion': FieldValue.serverTimestamp(),
          'estado': 'Pendiente',
          'items': [
            {
              'id': 'servicio_cancha_paddle',
              'nombre':
                  'Alquiler $_canchaSeleccionada ($_horaInicioSeleccionada:00 hs)',
              'precio': totalCalculado,
              'cantidad': 1,
              'es_producto_fisico': false,
            },
          ],
        });
      }

      final String? telefono = _datosSocio?['telefono'];
      if (telefono != null && telefono.isNotEmpty) {
        await _enviarConfirmacionReserva(
          telefono: telefono,
          nombreSocio: nombreSocio,
          cancha: _canchaSeleccionada!,
          fecha: _fechaSeleccionada,
          horaInicio: _horaInicioSeleccionada!,
          duracion: _duracionHoras,
        );
      }

      _snack('¡Reserva confirmada!', Colors.green);
      setState(() => _horaInicioSeleccionada = null);
    } catch (e) {
      _snack('Error al reservar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// OPCIÓN B: Disparo directo por HTTP a Render con formato oficial
  Future<void> _enviarConfirmacionReserva({
    required String telefono,
    required String nombreSocio,
    required String cancha,
    required DateTime fecha,
    required int horaInicio,
    required int duracion,
  }) async {
    String limpio = telefono.replaceAll(RegExp(r'\D'), '');
    if (limpio.isEmpty) return;
    if (limpio.startsWith('0')) limpio = limpio.substring(1);
    if (limpio.startsWith('15')) limpio = limpio.substring(2);
    if (!limpio.startsWith('54')) {
      limpio = '549$limpio';
    } else if (!limpio.startsWith('549')) {
      limpio = '549${limpio.substring(2)}';
    }

    final String fechaFormateada =
        "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
    final String horaInicioStr = "${horaInicio.toString().padLeft(2, '0')}:00";
    final String horaFinStr =
        "${(horaInicio + duracion).toString().padLeft(2, '0')}:00";

    final mensaje =
        '''
🎾 *¡RESERVA CONFIRMADA - CLUB AQUA & PADDLE!*

Hola *$nombreSocio*, confirmamos tu turno de pádel:

📍 *Cancha:* $cancha
📅 *Fecha:* $fechaFormateada
⏰ *Horario:* De $horaInicioStr a $horaFinStr hs ($duracion hr/s)

¡Te esperamos en el club! Por favor, recordá avisar con anticipación en caso de requerir cancelación.
''';

    try {
      await http.post(
        Uri.parse('https://servicio-whatsapp-oqua.onrender.com/send-whatsapp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': limpio, 'message': mensaje}),
      );
    } catch (e) {
      debugPrint('⚠️ Error al enviar mensaje por WhatsApp vía Render: $e');
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final fechaIdStr =
        "${_fechaSeleccionada.year}-${_fechaSeleccionada.month}-${_fechaSeleccionada.day}";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservar Cancha'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _canchaSeleccionada,
                        decoration: const InputDecoration(
                          labelText: 'Cancha',
                          border: OutlineInputBorder(),
                        ),
                        items: _canchasActivas
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (val) => setState(() {
                          _canchaSeleccionada = val;
                          _horaInicioSeleccionada = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Fecha: ${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.calendar_month),
                            label: const Text('Cambiar'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _fechaSeleccionada,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 14),
                                ),
                              );
                              if (picked != null) {
                                setState(() {
                                  _fechaSeleccionada = picked;
                                  _horaInicioSeleccionada = null;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('reservas_canchas')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final mapaReservas = {
                        for (var doc in snapshot.data!.docs)
                          doc.id: ReservaCanchaModel.fromFirestore(
                            doc.id,
                            doc.data() as Map<String, dynamic>,
                          ),
                      };

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 1.5,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: _horaCierre - _horaApertura,
                        itemBuilder: (context, index) {
                          final hora = _horaApertura + index;
                          bool ocupado = false;

                          mapaReservas.forEach((id, r) {
                            final fId =
                                "${r.fecha.year}-${r.fecha.month}-${r.fecha.day}";
                            if (fId == fechaIdStr &&
                                r.cancha == _canchaSeleccionada) {
                              if (hora >= r.horaInicio &&
                                  hora < (r.horaInicio + r.duracionHoras)) {
                                ocupado = true;
                              }
                            }
                          });

                          final esSeleccionado =
                              _horaInicioSeleccionada == hora;

                          return InkWell(
                            onTap: ocupado
                                ? null
                                : () => setState(
                                    () => _horaInicioSeleccionada = hora,
                                  ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: ocupado
                                    ? Colors.red.shade100
                                    : (esSeleccionado
                                          ? Colors.indigo
                                          : Colors.green.shade50),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${hora.toString().padLeft(2, '0')}:00 hs',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: esSeleccionado
                                          ? Colors.white
                                          : (ocupado
                                                ? Colors.red.shade900
                                                : Colors.green.shade900),
                                    ),
                                  ),
                                  Text(
                                    ocupado
                                        ? 'Ocupado'
                                        : (esSeleccionado
                                              ? 'Elegido'
                                              : 'Libre'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: esSeleccionado
                                          ? Colors.white70
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '\$${totalCalculado.toStringAsFixed(0)} ARS',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _horaInicioSeleccionada == null
                              ? null
                              : _confirmarReserva,
                          child: const Text('Confirmar Reserva'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
