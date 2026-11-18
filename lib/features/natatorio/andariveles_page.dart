import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'andarivel_reserva_model.dart';
import 'andarivel_reserva_repository.dart';

class AndarivelesPage extends StatefulWidget {
  const AndarivelesPage({super.key});

  @override
  State<AndarivelesPage> createState() => _AndarivelesPageState();
}

class _AndarivelesPageState extends State<AndarivelesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _fechaSeleccionada = DateTime.now();
  List<String> _andarivelesActivos = [
    'Andarivel 1',
    'Andarivel 2',
    'Andarivel 3',
    'Andarivel 4',
  ];
  int _horaApertura = 8;
  int _horaCierre = 21;
  Map<String, int> _cupoPorCategoria = {
    'Libre': 6,
    'Escuela': 12,
    'Rehabilitación': 4,
  };
  bool _cargandoConfig = true;

  List<QueryDocumentSnapshot> _todosLosSocios = [];
  bool _cargandoSocios = true;

  late Stream<QuerySnapshot> _cuposDelDiaStream;

  @override
  void initState() {
    super.initState();
    _cuposDelDiaStream = _streamCuposDelDia(_fechaSeleccionada);
    _cargarConfiguracion();
    _cargarSocios();
  }

  Stream<QuerySnapshot> _streamCuposDelDia(DateTime fecha) {
    final inicioDia = DateTime(fecha.year, fecha.month, fecha.day);
    return _firestore
        .collection('cupos_andariveles')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia))
        .where(
          'fecha',
          isLessThan: Timestamp.fromDate(inicioDia.add(const Duration(days: 1))),
        )
        .snapshots();
  }

  Future<void> _cargarConfiguracion() async {
    try {
      final docAndariveles = await _firestore
          .collection('configuracion_natatorio')
          .doc('andariveles')
          .get();
      if (docAndariveles.exists && docAndariveles.data()?['lista'] != null) {
        _andarivelesActivos = List<String>.from(
          docAndariveles.data()!['lista'],
        );
      }

      final docAjustes = await _firestore
          .collection('configuracion_natatorio')
          .doc('ajustes_globales')
          .get();
      if (docAjustes.exists && docAjustes.data() != null) {
        final d = docAjustes.data()!;
        _horaApertura = (d['horaApertura'] as num?)?.toInt() ?? 8;
        _horaCierre = (d['horaCierre'] as num?)?.toInt() ?? 21;
        if (d['cupoPorCategoria'] is Map) {
          _cupoPorCategoria = Map<String, int>.from(
            (d['cupoPorCategoria'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ),
          );
        }
      }
    } catch (e) {
      _snack('Error al cargar configuración: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargandoConfig = false);
    }
  }

  Future<void> _cargarSocios() async {
    try {
      final snap = await _firestore
          .collection('socios')
          .where('activo', isEqualTo: true)
          .get();
      _todosLosSocios = snap.docs;
    } catch (_) {
      // Sin socios cargados igual se puede reservar para invitados.
    } finally {
      if (mounted) setState(() => _cargandoSocios = false);
    }
  }

  Future<void> _guardarConfiguracion() async {
    await _firestore
        .collection('configuracion_natatorio')
        .doc('andariveles')
        .set({'lista': _andarivelesActivos});
    await _firestore
        .collection('configuracion_natatorio')
        .doc('ajustes_globales')
        .set({
          'horaApertura': _horaApertura,
          'horaCierre': _horaCierre,
          'cupoPorCategoria': _cupoPorCategoria,
        });
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _fechaIdStr(DateTime f) => "${f.year}-${f.month}-${f.day}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Andariveles - Natatorio'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configurar andariveles y cupos',
            onPressed: _cargandoConfig ? null : _abrirDialogoConfiguracion,
          ),
        ],
      ),
      body: _cargandoConfig
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Fecha: ${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Cambiar fecha'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _fechaSeleccionada,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 30),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 30),
                            ),
                          );
                          if (picked != null) {
                            setState(() {
                              _fechaSeleccionada = picked;
                              _cuposDelDiaStream = _streamCuposDelDia(picked);
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _cuposDelDiaStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final Map<String, Map<String, dynamic>> cuposPorSlot = {
                        for (var doc in snapshot.data!.docs)
                          doc.id: doc.data() as Map<String, dynamic>,
                      };

                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: _andarivelesActivos.map((andarivel) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      andarivel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: List.generate(
                                        _horaCierre - _horaApertura,
                                        (i) {
                                          final hora = _horaApertura + i;
                                          final andarivelLimpio = andarivel
                                              .replaceAll(' ', '');
                                          final slotId =
                                              '${_fechaIdStr(_fechaSeleccionada)}_${andarivelLimpio}_${hora}hs';
                                          final cupoData =
                                              cuposPorSlot[slotId];
                                          final int ocupados =
                                              (cupoData?['ocupados']
                                                      as num?)
                                                  ?.toInt() ??
                                              0;
                                          final String? categoria =
                                              cupoData?['categoria']
                                                  ?.toString();
                                          final int cupoMaximo = categoria !=
                                                  null
                                              ? (_cupoPorCategoria[categoria] ??
                                                    0)
                                              : 0;
                                          final bool lleno = categoria !=
                                                  null &&
                                              ocupados >= cupoMaximo;

                                          return InkWell(
                                            onTap: () => _abrirDialogoSlot(
                                              andarivel,
                                              hora,
                                              categoria,
                                              ocupados,
                                            ),
                                            child: Container(
                                              width: 110,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 10,
                                                horizontal: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: categoria == null
                                                    ? Colors.green.shade50
                                                    : (lleno
                                                        ? Colors.red.shade100
                                                        : Colors
                                                            .blue.shade50),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: categoria == null
                                                      ? Colors.green.shade300
                                                      : (lleno
                                                          ? Colors
                                                              .red.shade300
                                                          : Colors
                                                              .blue.shade300),
                                                ),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    '${hora.toString().padLeft(2, '0')}:00 hs',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    categoria == null
                                                        ? 'Libre (sin asignar)'
                                                        : '$categoria · $ocupados/$cupoMaximo',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                    textAlign:
                                                        TextAlign.center,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _abrirDialogoSlot(
    String andarivel,
    int hora,
    String? categoriaActual,
    int ocupadosActuales,
  ) async {
    // Lectura puntual (no listener) sólo al abrir el turno: lista de quiénes
    // están anotados, para poder cancelarlos si hace falta.
    final reservasSnap = await _firestore
        .collection('reservas_andariveles')
        .where('andarivel', isEqualTo: andarivel)
        .where('horaInicio', isEqualTo: hora)
        .where(
          'fecha',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime(
              _fechaSeleccionada.year,
              _fechaSeleccionada.month,
              _fechaSeleccionada.day,
            ),
          ),
        )
        .where(
          'fecha',
          isLessThan: Timestamp.fromDate(
            DateTime(
              _fechaSeleccionada.year,
              _fechaSeleccionada.month,
              _fechaSeleccionada.day,
            ).add(const Duration(days: 1)),
          ),
        )
        .get();

    final reservasActuales = reservasSnap.docs
        .map((d) => AndarivelReservaModel.fromFirestore(d.id, d.data()))
        .toList();

    if (!mounted) return;

    String categoriaElegida =
        categoriaActual ?? _cupoPorCategoria.keys.first;
    Map<String, dynamic>? socioElegido;
    final nombreCtrl = TextEditingController();
    String busquedaSocio = '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final cupoMaximo = _cupoPorCategoria[categoriaElegida] ?? 0;
          return AlertDialog(
            title: Text('$andarivel · ${hora.toString().padLeft(2, '0')}:00 hs'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reservasActuales.isNotEmpty) ...[
                      const Text(
                        'Anotados:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ...reservasActuales.map(
                        (r) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.nombreCliente),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () async {
                              await cancelarAndariveloAtomica(
                                firestore: _firestore,
                                reserva: r,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              _snack(
                                '🔓 Lugar liberado en $andarivel.',
                                Colors.green,
                              );
                            },
                          ),
                        ),
                      ),
                      const Divider(),
                    ],
                    if (categoriaActual == null)
                      DropdownButtonFormField<String>(
                        initialValue: categoriaElegida,
                        decoration: const InputDecoration(
                          labelText: 'Categoría para este turno',
                        ),
                        items: _cupoPorCategoria.keys
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  '$c (cupo ${_cupoPorCategoria[c]})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setModalState(
                          () => categoriaElegida = v ?? categoriaElegida,
                        ),
                      )
                    else
                      Text(
                        'Categoría de este turno: $categoriaActual (cupo $cupoMaximo)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 12),
                    if ((categoriaActual == null &&
                            0 < cupoMaximo) ||
                        (categoriaActual != null &&
                            ocupadosActuales < cupoMaximo)) ...[
                      if (socioElegido == null) ...[
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Nombre (invitado) o buscar socio',
                            prefixIcon: Icon(Icons.search),
                          ),
                          controller: nombreCtrl,
                          onChanged: (v) => setModalState(
                            () => busquedaSocio = v.toLowerCase(),
                          ),
                        ),
                        if (busquedaSocio.length >= 3)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 140),
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Builder(
                              builder: (_) {
                                if (_cargandoSocios) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: LinearProgressIndicator(),
                                  );
                                }
                                final filtrados = _todosLosSocios.where((doc) {
                                  final d =
                                      doc.data() as Map<String, dynamic>;
                                  final nombre = (d['nombre'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  final dni = (d['dni'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  return nombre.contains(busquedaSocio) ||
                                      dni.contains(busquedaSocio);
                                }).toList();
                                if (filtrados.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text(
                                      'Sin coincidencias.',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  );
                                }
                                return ListView(
                                  shrinkWrap: true,
                                  children: filtrados.map((doc) {
                                    final d = doc.data()
                                        as Map<String, dynamic>;
                                    return ListTile(
                                      dense: true,
                                      title: Text(d['nombre'] ?? ''),
                                      subtitle: Text(
                                        'DNI: ${d['dni'] ?? 'S/D'}',
                                      ),
                                      onTap: () => setModalState(() {
                                        socioElegido = {
                                          'id': doc.id,
                                          ...d,
                                        };
                                      }),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ),
                      ] else
                        Card(
                          color: const Color(0xFFEFF6FF),
                          child: ListTile(
                            leading: const Icon(
                              Icons.check_circle,
                              color: Colors.blue,
                            ),
                            title: Text(socioElegido!['nombre'] ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () =>
                                  setModalState(() => socioElegido = null),
                            ),
                          ),
                        ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Cupo completo para este turno.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              if ((categoriaActual == null && 0 < cupoMaximo) ||
                  (categoriaActual != null && ocupadosActuales < cupoMaximo))
                ElevatedButton(
                  onPressed:
                      (socioElegido == null && nombreCtrl.text.trim().isEmpty)
                      ? null
                      : () async {
                          final nuevaReserva = AndarivelReservaModel(
                            id: 'sin-usar',
                            andarivel: andarivel,
                            categoria: categoriaElegida,
                            nombreCliente: socioElegido != null
                                ? (socioElegido!['nombre'] ?? '')
                                : nombreCtrl.text.trim(),
                            socioId: socioElegido?['id'] as String?,
                            fecha: _fechaSeleccionada,
                            horaInicio: hora,
                          );
                          try {
                            await reservarAndariveloAtomica(
                              firestore: _firestore,
                              reserva: nuevaReserva,
                              cupoMaximo: cupoMaximo,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack('✅ Reserva confirmada.', Colors.green);
                          } on CupoLlenoException {
                            _snack('Ese turno ya está completo.', Colors.red);
                          } on YaAnotadoException {
                            _snack(
                              'Esa persona ya está anotada en ese turno.',
                              Colors.orange,
                            );
                          } on CategoriaDelTurnoException {
                            _snack(
                              'Ese turno ya quedó fijado con otra categoría.',
                              Colors.red,
                            );
                          } catch (e) {
                            _snack('Error: $e', Colors.red);
                          }
                        },
                  child: const Text('Confirmar'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _abrirDialogoConfiguracion() async {
    final andarivelesCtrl = TextEditingController(
      text: _andarivelesActivos.join(', '),
    );
    final horaAperturaCtrl = TextEditingController(
      text: _horaApertura.toString(),
    );
    final horaCierreCtrl = TextEditingController(
      text: _horaCierre.toString(),
    );
    final cupoCtrls = {
      for (var c in _cupoPorCategoria.keys)
        c: TextEditingController(text: _cupoPorCategoria[c].toString()),
    };

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar Natatorio'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: andarivelesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Andariveles (separados por coma)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: horaAperturaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Hora apertura',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: horaCierreCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Hora cierre',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Cupo máximo por categoría',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...cupoCtrls.entries.map(
                  (e) => TextField(
                    controller: e.value,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: e.key),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _andarivelesActivos = andarivelesCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                _horaApertura =
                    int.tryParse(horaAperturaCtrl.text) ?? _horaApertura;
                _horaCierre =
                    int.tryParse(horaCierreCtrl.text) ?? _horaCierre;
                _cupoPorCategoria = {
                  for (var e in cupoCtrls.entries)
                    e.key: int.tryParse(e.value.text) ?? 0,
                };
              });
              await _guardarConfiguracion();
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('✅ Configuración guardada.', Colors.green);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
