import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'partido_abierto_model.dart';
import 'partido_abierto_repository.dart';
import 'reserva_cancha_model.dart';
import 'reserva_cancha_repository.dart';

const List<String> categoriasPartidoAbierto = [
  '8va (Iniciación)',
  '7ma',
  '6ta',
  '5ta',
  '4ta (Avanzado)',
];

class CrearPartidoAbiertoPage extends StatefulWidget {
  const CrearPartidoAbiertoPage({super.key});

  @override
  State<CrearPartidoAbiertoPage> createState() =>
      _CrearPartidoAbiertoPageState();
}

class _CrearPartidoAbiertoPageState extends State<CrearPartidoAbiertoPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _cargando = true;
  Map<String, dynamic>? _datosSocio;

  double _precioBaseSocio = 4500.0;
  int _horaInicioCargaLuz = 20;
  double _plusLuzAnexo = 1500.0;
  int _horaApertura = 8;
  int _horaCierre = 23;
  List<String> _canchasActivas = [];

  DateTime _fechaSeleccionada = DateTime.now();
  String? _canchaSeleccionada;
  int? _horaInicioSeleccionada;
  String _categoriaSeleccionada = categoriasPartidoAbierto[2];

  @override
  void initState() {
    super.initState();
    _cargarAjustes();
  }

  Future<void> _cargarAjustes() async {
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
      _canchasActivas = (docCanchas.exists && docCanchas.data()?['lista'] != null)
          ? List<String>.from(docCanchas.data()!['lista'])
          : ['Cancha 1 Cristal', 'Cancha 2 Cristal', 'Cancha 3 Muro'];
      if (_canchasActivas.isNotEmpty) {
        _canchaSeleccionada = _canchasActivas.first;
      }
    } catch (e) {
      _snack('Error al cargar configuración: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  double get _precioTotalCancha {
    if (_horaInicioSeleccionada == null) return 0.0;
    double total = _precioBaseSocio;
    if (_horaInicioSeleccionada! >= _horaInicioCargaLuz) {
      total += _plusLuzAnexo;
    }
    return total;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _confirmarCreacion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null ||
        _canchaSeleccionada == null ||
        _horaInicioSeleccionada == null) {
      _snack('Seleccioná cancha y horario.', Colors.orange);
      return;
    }

    final fechaIdStr =
        "${_fechaSeleccionada.year}-${_fechaSeleccionada.month}-${_fechaSeleccionada.day}";
    final canchaLimpia = _canchaSeleccionada!.replaceAll(' ', '');
    final reservaId =
        "${fechaIdStr}_${canchaLimpia}_${_horaInicioSeleccionada}hs_duracion1h";
    final String nombreSocio = _datosSocio != null
        ? '${_datosSocio!['nombre'] ?? ''} ${_datosSocio!['apellido'] ?? ''}'
              .trim()
        : 'Socio';

    setState(() => _cargando = true);
    try {
      await crearPartidoAbiertoAtomica(
        firestore: _firestore,
        reserva: ReservaCanchaModel(
          id: reservaId,
          cancha: _canchaSeleccionada!,
          nombreCliente: nombreSocio,
          socioId: user.uid,
          fecha: _fechaSeleccionada,
          horaInicio: _horaInicioSeleccionada!,
          duracionHoras: 1,
          precio: _precioTotalCancha,
          metodoPago: 'Cuenta Corriente',
        ),
        categoria: _categoriaSeleccionada,
        organizadorId: user.uid,
        organizadorNombre: nombreSocio,
      );
      if (mounted) {
        _snack(
          '🎾 ¡Partido Abierto creado! Se cobrará tu cuarta parte (\$${(_precioTotalCancha / PartidoAbiertoModel.cupoJugadores).toStringAsFixed(0)}) en caja.',
          Colors.green,
        );
        Navigator.pop(context);
      }
    } on HorarioOcupadoException {
      _snack('Ese horario ya fue reservado. Elegí otro.', Colors.red);
    } catch (e) {
      _snack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Partido Abierto'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reservá la cancha y sumá hasta 3 jugadores más. El '
                    'costo se divide entre los 4 (cada uno se anota y paga '
                    'su parte en caja).',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: _canchaSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Cancha',
                      border: OutlineInputBorder(),
                    ),
                    items: _canchasActivas
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _canchaSeleccionada = v;
                      _horaInicioSeleccionada = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _categoriaSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Categoría del partido',
                      border: OutlineInputBorder(),
                    ),
                    items: categoriasPartidoAbierto
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(
                      () => _categoriaSeleccionada = v ?? _categoriaSeleccionada,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    tileColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: const Icon(Icons.calendar_month),
                    title: Text(
                      'Fecha: ${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _fechaSeleccionada,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 14)),
                      );
                      if (picked != null) {
                        setState(() {
                          _fechaSeleccionada = picked;
                          _horaInicioSeleccionada = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Horario',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(_horaCierre - _horaApertura, (i) {
                      final hora = _horaApertura + i;
                      final seleccionado = _horaInicioSeleccionada == hora;
                      return ChoiceChip(
                        label: Text('${hora.toString().padLeft(2, '0')}:00'),
                        selected: seleccionado,
                        onSelected: (_) =>
                            setState(() => _horaInicioSeleccionada = hora),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  if (_horaInicioSeleccionada != null)
                    Card(
                      color: const Color(0xFFEFF6FF),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Total cancha: \$${_precioTotalCancha.toStringAsFixed(0)} · '
                          'Tu parte (1/4): \$${(_precioTotalCancha / PartidoAbiertoModel.cupoJugadores).toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
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
                          : _confirmarCreacion,
                      child: const Text('Crear Partido Abierto'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
