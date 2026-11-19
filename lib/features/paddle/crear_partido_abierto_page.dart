import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cancha_padel_model.dart';
import 'cancha_padel_repository.dart';
import 'paddle_ids.dart';
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

const List<String> posicionesPadel = ['Indistinto', 'Drive', 'Revés'];

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
  String? _socioDocId;

  double _precioBaseSocio = 4500.0;
  int _horaInicioCargaLuz = 20;
  double _plusLuzAnexo = 1500.0;
  int _horaApertura = 8;
  int _horaCierre = 23;
  List<String> _canchasActivas = [];
  List<CanchaPadelModel> _canchasPadel = [];

  CanchaPadelModel? _canchaPadelDe(String nombre) {
    for (final c in _canchasPadel) {
      if (c.nombre == nombre) return c;
    }
    return null;
  }

  DateTime _fechaSeleccionada = DateTime.now();
  String? _canchaSeleccionada;
  int? _horaInicioSeleccionada;
  String _categoriaSeleccionada = categoriasPartidoAbierto[2];

  // 🎾 Perfil de jugador (Fase 6): categoría/posición propias, editables
  // acá mismo antes de crear el partido.
  String? _categoriaPadelPropia;
  String _posicionPadelPropia = posicionesPadel[0];
  bool _guardandoPerfilPadel = false;

  @override
  void initState() {
    super.initState();
    _cargarAjustes();
  }

  Future<void> _cargarAjustes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 🚨 El id del doc 'socios/{id}' NO es el uid de Auth — buscar por
        // 'usuarioUid' (mismo criterio que partidos_abiertos_page.dart).
        // Antes esto buscaba .doc(user.uid) directo: para cualquier socio
        // migrado (id de alta distinto del uid) nunca encontraba la ficha,
        // dejaba _datosSocio null (el nombre caía a "Socio" genérico) y,
        // peor, _confirmarCreacion() terminaba mandando el auth.uid como si
        // fuera el id de socios/{id} — la regla de creación de
        // 'partidos_abiertos' lo rechazaba siempre con permission-denied.
        final querySocio = await _firestore
            .collection('socios')
            .where('usuarioUid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (querySocio.docs.isNotEmpty) {
          _socioDocId = querySocio.docs.first.id;
          _datosSocio = querySocio.docs.first.data();
          _categoriaPadelPropia = _datosSocio?['categoriaPadel']?.toString();
          _posicionPadelPropia =
              _datosSocio?['posicionPadel']?.toString() ?? posicionesPadel[0];
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
        _horaInicioCargaLuz = (d['hora_inicio_luz'] as num?)?.toInt() ?? 20;
        _plusLuzAnexo =
            (d['precio_adicional_luz'] as num?)?.toDouble() ?? 1500.0;
        _horaApertura = (d['hora_apertura'] as num?)?.toInt() ?? 8;
        _horaCierre = (d['hora_cierre'] as num?)?.toInt() ?? 23;
      }

      _canchasPadel = await obtenerCanchasPadel(_firestore);
      _canchasActivas = await obtenerNombresCanchasActivas(_firestore);
      if (_canchasActivas.isNotEmpty) {
        _canchaSeleccionada = _canchasActivas.first;
      }
    } catch (e) {
      _snack('Error al cargar configuración: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardarPerfilPadel(String categoria, String posicion) async {
    if (_socioDocId == null) return;
    setState(() => _guardandoPerfilPadel = true);
    try {
      await _firestore.collection('socios').doc(_socioDocId).update({
        'categoriaPadel': categoria,
        'posicionPadel': posicion,
      });
      if (mounted) {
        setState(() {
          _categoriaPadelPropia = categoria;
          _posicionPadelPropia = posicion;
        });
        _snack('✅ Perfil de pádel actualizado.', Colors.green);
      }
    } catch (e) {
      _snack('Error al guardar tu perfil: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _guardandoPerfilPadel = false);
    }
  }

  double get _precioTotalCancha {
    if (_horaInicioSeleccionada == null || _canchaSeleccionada == null) {
      return 0.0;
    }
    final c = _canchaPadelDe(_canchaSeleccionada!);
    final base = c?.precioBaseHoraSocio ?? _precioBaseSocio;
    final horaLuz = c?.horaInicioLuz ?? _horaInicioCargaLuz;
    final plusLuz = c?.precioAdicionalLuz ?? _plusLuzAnexo;
    return _horaInicioSeleccionada! >= horaLuz ? base + plusLuz : base;
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
        _socioDocId == null ||
        _canchaSeleccionada == null ||
        _horaInicioSeleccionada == null) {
      _snack(
        _socioDocId == null
            ? 'No encontramos tu ficha de socio. Contactá a administración.'
            : 'Seleccioná cancha y horario.',
        Colors.orange,
      );
      return;
    }

    final reservaId = idReservaCancha(
      fecha: _fechaSeleccionada,
      cancha: _canchaSeleccionada!,
      horaInicio: _horaInicioSeleccionada!,
      duracionHoras: 1,
    );
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
          socioId: _socioDocId,
          fecha: _fechaSeleccionada,
          horaInicio: _horaInicioSeleccionada!,
          duracionHoras: 1,
          precio: _precioTotalCancha,
          metodoPago: 'Cuenta Corriente',
        ),
        categoria: _categoriaSeleccionada,
        organizadorId: _socioDocId!,
        organizadorNombre: nombreSocio,
        ventaSocioId: user.uid,
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
                  if (_categoriaPadelPropia != null &&
                      _categoriaPadelPropia != _categoriaSeleccionada)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '⚠️ Tu categoría registrada es $_categoriaPadelPropia — '
                        'distinta a la de este partido. Podés crearlo igual.',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _buildPerfilPadelCard(),
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

  Widget _buildPerfilPadelCard() {
    // Estado local del diálogo de edición: arranca en lo ya guardado (o el
    // default) y sólo se confirma al tocar "Guardar".
    String categoriaEdit = _categoriaPadelPropia ?? categoriasPartidoAbierto[2];
    String posicionEdit = _posicionPadelPropia;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined, color: Colors.indigo),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _categoriaPadelPropia != null
                  ? 'Tu categoría: $_categoriaPadelPropia · $_posicionPadelPropia'
                  : 'Todavía no cargaste tu categoría de pádel.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _guardandoPerfilPadel
                ? null
                : () async {
                    final resultado = await showDialog<List<String>>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setModalState) => AlertDialog(
                          title: const Text('Tu perfil de pádel'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: categoriaEdit,
                                decoration: const InputDecoration(
                                  labelText: 'Categoría',
                                ),
                                items: categoriasPartidoAbierto
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setModalState(
                                  () => categoriaEdit = v ?? categoriaEdit,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: posicionEdit,
                                decoration: const InputDecoration(
                                  labelText: 'Posición preferida',
                                ),
                                items: posicionesPadel
                                    .map(
                                      (p) => DropdownMenuItem(
                                        value: p,
                                        child: Text(p),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setModalState(
                                  () => posicionEdit = v ?? posicionEdit,
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, [
                                categoriaEdit,
                                posicionEdit,
                              ]),
                              child: const Text('Guardar'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (resultado != null) {
                      await _guardarPerfilPadel(resultado[0], resultado[1]);
                    }
                  },
            child: Text(_categoriaPadelPropia != null ? 'Editar' : 'Cargar'),
          ),
        ],
      ),
    );
  }
}
