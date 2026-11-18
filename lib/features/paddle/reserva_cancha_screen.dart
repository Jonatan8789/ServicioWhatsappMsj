import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'reserva_cancha_model.dart';
import 'reserva_cancha_repository.dart';

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
  String? _socioDocId;

  // 🚨 Antes el stream se armaba de nuevo (nueva instancia de Stream) en
  // CADA build(), incluyendo los que dispara elegir una cancha u horario —
  // StreamBuilder detecta el cambio de identidad del stream y cancela/
  // resuscribe el listener de Firestore aunque la consulta real (mismo día)
  // no haya cambiado. Ahora se cachea y sólo se reconstruye cuando cambia
  // la fecha seleccionada.
  late Stream<QuerySnapshot> _reservasDelDiaStream;

  @override
  void initState() {
    super.initState();
    _reservasDelDiaStream = _streamReservasDelDia(_fechaSeleccionada);
    _cargarAjustesGlobales();
  }

  Stream<QuerySnapshot> _streamReservasDelDia(DateTime fecha) {
    final inicioDia = DateTime(fecha.year, fecha.month, fecha.day);
    return _firestore
        .collection('reservas_canchas')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia))
        .where(
          'fecha',
          isLessThan: Timestamp.fromDate(inicioDia.add(const Duration(days: 1))),
        )
        .snapshots();
  }

  Future<void> _cargarAjustesGlobales() async {
    setState(() => _cargando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 🚨 El id del documento 'socios/{id}' NO es el uid de Auth — son
        // altas migradas/creadas por el admin con id propio, vinculadas
        // recién después vía el campo 'usuarioUid'. Buscar por
        // .doc(user.uid) directo nunca encontraba el documento real de un
        // socio migrado, dejaba _datosSocio null (nombre quedaba "Socio
        // Mobile") y, peor, socioId se guardaba como el uid de Auth: la
        // regla de creación de 'reservas_canchas' busca
        // socios/{socioId}.usuarioUid, así que con el uid de Auth ahí
        // jamás matcheaba y el alta se rechazaba por permisos.
        final querySocio = await _firestore
            .collection('socios')
            .where('usuarioUid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (querySocio.docs.isNotEmpty) {
          _socioDocId = querySocio.docs.first.id;
          _datosSocio = querySocio.docs.first.data();
        }
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
    if (_socioDocId == null) {
      _snack(
        'No encontramos tu ficha de socio. Contactá a administración.',
        Colors.red,
      );
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
      socioId: _socioDocId,
      fecha: _fechaSeleccionada,
      horaInicio: _horaInicioSeleccionada!,
      duracionHoras: _duracionHoras,
      precio: totalCalculado,
      metodoPago: 'Cuenta Corriente',
    );

    try {
      // 🚨 Antes chequeaba solapamiento con un `get()` y recién después
      // escribía la reserva aparte (TOCTOU) — ver reserva_cancha_repository.dart.
      try {
        await reservarCanchaAtomica(
          firestore: _firestore,
          reserva: nuevaReserva,
        );
      } on HorarioOcupadoException {
        _snack('¡El horario ya fue reservado!', Colors.red);
        return;
      }

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

  /// 🚨 Antes disparaba el HTTP directo a Render, que exige un ID token de
  /// admin — un socio nunca lo tiene, así que esta confirmación fallaba
  /// siempre en silencio (401). Ahora pasa por la Cloud Function
  /// 'notificarWhatsappSocio', que valida que quien llama es un socio real
  /// y manda el mensaje a SU PROPIO teléfono ya registrado (nunca a uno
  /// arbitrario), "prestando" un token de admin del lado del servidor.
  Future<void> _enviarConfirmacionReserva({
    required String telefono,
    required String nombreSocio,
    required String cancha,
    required DateTime fecha,
    required int horaInicio,
    required int duracion,
  }) async {
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
      final callable = FirebaseFunctions.instance.httpsCallable(
        'notificarWhatsappSocio',
      );
      final resp = await callable.call({
        'tipo': 'notificar_propio',
        'mensaje': mensaje,
      });
      if (resp.data['success'] != true) {
        debugPrint('⚠️ WhatsApp no enviado: ${resp.data['error']}');
      }
    } catch (e) {
      debugPrint('⚠️ Error al enviar mensaje por WhatsApp: $e');
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  static const List<String> _nombresDias = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  // 🔁 TURNO FIJO SEMANAL: muestra el turno fijo activo del socio (si
  // tiene uno) con opción de cancelarlo, y reusa la cancha/horario/fecha
  // ya elegidos arriba para armar uno nuevo — no hace falta un formulario
  // aparte, la fecha elegida define el día de la semana que se repite.
  Widget _buildTurnoFijoActivo() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('turnos_recurrentes_canchas')
          .where('socioId', isEqualTo: _socioDocId)
          .where('activo', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final doc = snapshot.data!.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final String dia =
            _nombresDias[((data['diaSemana'] as num?)?.toInt() ?? 1) - 1];
        return Container(
          width: double.infinity,
          color: Colors.indigo.shade50,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.event_repeat_rounded, color: Colors.indigo),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Turno fijo: $dia ${data['horaInicio']}:00hs - ${data['cancha']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => _cancelarTurnoFijo(doc.id),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelarTurnoFijo(String turnoId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar turno fijo?'),
        content: const Text(
          'Se van a liberar las semanas futuras que todavía no pasaron.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('cancelarTurnoRecurrenteCancha')
          .call({'turnoId': turnoId});
      if (mounted) _snack('Turno fijo cancelado.', Colors.orange);
    } catch (e) {
      if (mounted) _snack('No se pudo cancelar: $e', Colors.red);
    }
  }

  Future<void> _hacerTurnoFijo() async {
    if (_canchaSeleccionada == null || _horaInicioSeleccionada == null) {
      _snack('Elegí cancha y horario primero.', Colors.orange);
      return;
    }
    final String dia = _nombresDias[_fechaSeleccionada.weekday - 1];
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Hacer turno fijo?'),
        content: Text(
          'Vas a reservar todos los $dia a las $_horaInicioSeleccionada:00hs '
          'en $_canchaSeleccionada, automáticamente, hasta que lo canceles.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _cargando = true);
    try {
      final resp = await FirebaseFunctions.instance
          .httpsCallable('crearTurnoRecurrenteCanchaSocio')
          .call({
            'cancha': _canchaSeleccionada,
            'diaSemana': _fechaSeleccionada.weekday,
            'horaInicio': _horaInicioSeleccionada,
            'duracionHoras': _duracionHoras,
          });
      if (!mounted) return;
      if (resp.data['success'] == true) {
        _snack('¡Turno fijo creado!', Colors.green);
      } else {
        _snack(
          resp.data['error'] ?? 'No se pudo crear el turno fijo.',
          Colors.red,
        );
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
                if (_socioDocId != null) _buildTurnoFijoActivo(),
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
                                  _reservasDelDiaStream = _streamReservasDelDia(
                                    picked,
                                  );
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
                    stream: _reservasDelDiaStream,
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
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            Icons.event_repeat_rounded,
                            size: 18,
                          ),
                          label: const Text('Hacer turno fijo semanal'),
                          onPressed: _horaInicioSeleccionada == null
                              ? null
                              : _hacerTurnoFijo,
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
