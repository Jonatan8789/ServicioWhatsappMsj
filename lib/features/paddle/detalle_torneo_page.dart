import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inscripcion_torneo_dialog.dart';
import 'torneo_categorias.dart';
import 'partido_torneo_model.dart';
import 'bracket_generator_service.dart';
import 'torneo_firestore_service.dart';

const _kPrimary = Color(0xFF0A3B43);

class DetalleTorneoPage extends StatefulWidget {
  final String torneoId;
  final bool esAdmin;

  const DetalleTorneoPage({
    super.key,
    required this.torneoId,
    this.esAdmin = false,
  });

  @override
  State<DetalleTorneoPage> createState() => _DetalleTorneoPageState();
}

class _DetalleTorneoPageState extends State<DetalleTorneoPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  TabController? _tabController;
  bool _procesando = false;

  void _abrirModalInscripcion(Map<String, dynamic> torneoData) async {
    final bool? inscripto = await showDialog<bool>(
      context: context,
      builder: (context) => InscripcionTorneoDialog(
        torneoId: widget.torneoId,
        nombreTorneo: torneoData['nombre'] ?? 'Torneo de Pádel',
        precioInscripcion:
            (torneoData['precioInscripcion'] as num?)?.toDouble() ?? 0.0,
        categoriaTorneo: torneoData['categoria']?.toString() ?? '5ta',
      ),
    );

    if (inscripto == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pareja inscripta e ingreso asentado correctamente.'),
          backgroundColor: _kPrimary,
        ),
      );
    }
  }

  void _snack(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<List<ParejaSeed>> _obtenerParejasInscriptas() async {
    final snap = await _firestore
        .collection('torneos')
        .doc(widget.torneoId)
        .collection('parejas_inscriptas')
        .get();
    final parejas = snap.docs.map((d) {
      final data = d.data();
      final j1 = data['jugador1']?['nombreCompleto'] ?? '?';
      final j2 = data['jugador2']?['nombreCompleto'] ?? '?';
      return ParejaSeed(id: d.id, nombre: '$j1 / $j2');
    }).toList();
    parejas.shuffle(Random()); // sorteo al azar, como un sorteo real en vivo
    return parejas;
  }

  Future<void> _confirmarYSortear(Map<String, dynamic> torneoData) async {
    final formato =
        torneoData['formatoElegido'] ?? TorneoCategorias.formatos[0];
    final esFaseDeGrupos = formato == TorneoCategorias.formatos[2];

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Sortear el torneo?'),
        content: Text(
          esFaseDeGrupos
              ? 'Se armarán las zonas y el fixture de todos contra todos. '
                    'Ya no se van a poder anotar más parejas.'
              : 'Se armará la llave de eliminación simple. Ya no se van a '
                    'poder anotar más parejas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sortear',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando = true);
    try {
      final parejas = await _obtenerParejasInscriptas();
      if (parejas.length < 2) {
        throw Exception('Hacen falta al menos 2 parejas inscriptas.');
      }

      if (esFaseDeGrupos) {
        final cantidadGrupos =
            (torneoData['cantidadGruposElegida'] as num?)?.toInt() ?? 4;
        final cantidadGruposReal = min(
          cantidadGrupos,
          max(1, parejas.length ~/ 2),
        );
        await TorneoFirestoreService.generarFaseDeGrupos(
          torneoId: widget.torneoId,
          parejasSembradas: parejas,
          cantidadGrupos: cantidadGruposReal,
        );
      } else {
        await TorneoFirestoreService.generarSorteoEliminacionSimple(
          torneoId: widget.torneoId,
          parejasSembradas: parejas,
        );
      }
      _snack('🎾 ¡Torneo sorteado! Ya se armó el fixture.');
    } catch (e) {
      _snack('Error al sortear: $e', esError: true);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _generarLlaveDesdeGrupos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Armar la llave eliminatoria?'),
        content: const Text(
          'Se van a clasificar los 2 primeros de cada zona a la llave de '
          'eliminación directa. Todos los partidos de grupos tienen que '
          'estar cargados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Armar Llave',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando = true);
    try {
      await TorneoFirestoreService.generarLlaveDesdeGrupos(
        torneoId: widget.torneoId,
        clasificadosPorGrupo: 2,
      );
      _snack('🏆 ¡Llave eliminatoria armada con los clasificados!');
    } catch (e) {
      _snack('Error: $e', esError: true);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('torneos').doc(widget.torneoId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final torneoData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final String faseActual = torneoData['faseActual'] ?? 'inscripcion';
        final String formato =
            torneoData['formatoElegido'] ?? TorneoCategorias.formatos[0];
        final bool esFaseDeGrupos = formato == TorneoCategorias.formatos[2];

        final tabs = <Tab>[
          const Tab(text: 'Inscripciones', icon: Icon(Icons.group, size: 18)),
          if (esFaseDeGrupos && faseActual != 'inscripcion')
            const Tab(text: 'Grupos', icon: Icon(Icons.grid_view, size: 18)),
          if (faseActual == 'llave' || faseActual == 'finalizado')
            const Tab(
              text: 'Llave',
              icon: Icon(Icons.account_tree, size: 18),
            ),
        ];

        _tabController ??= TabController(length: tabs.length, vsync: this);
        if (_tabController!.length != tabs.length) {
          _tabController!.dispose();
          _tabController = TabController(length: tabs.length, vsync: this);
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(torneoData['nombre'] ?? 'Detalle del Torneo'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            bottom: TabBar(
              controller: _tabController,
              tabs: tabs,
              indicatorColor: Colors.cyanAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
            ),
          ),
          floatingActionButton: _procesando
              ? const FloatingActionButton(
                  onPressed: null,
                  backgroundColor: _kPrimary,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _construirFab(torneoData, faseActual, esFaseDeGrupos),
          body: Column(
            children: [
              _buildEncabezado(torneoData, faseActual, formato),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTabInscripciones(faseActual),
                    if (esFaseDeGrupos && faseActual != 'inscripcion')
                      _buildTabGrupos(torneoData),
                    if (faseActual == 'llave' || faseActual == 'finalizado')
                      _buildTabLlave(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _construirFab(
    Map<String, dynamic> torneoData,
    String faseActual,
    bool esFaseDeGrupos,
  ) {
    if (faseActual == 'inscripcion') {
      if (widget.esAdmin) {
        return FloatingActionButton.extended(
          onPressed: () => _abrirModalInscripcion(torneoData),
          backgroundColor: _kPrimary,
          icon: const Icon(Icons.group_add, color: Colors.white),
          label: const Text(
            'Inscribir Pareja',
            style: TextStyle(color: Colors.white),
          ),
        );
      }
      return FloatingActionButton.extended(
        onPressed: () => _abrirModalInscripcion(torneoData),
        backgroundColor: _kPrimary,
        icon: const Icon(Icons.group_add, color: Colors.white),
        label: const Text(
          'Inscribir Pareja',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    if (widget.esAdmin && esFaseDeGrupos && faseActual == 'grupos') {
      return FloatingActionButton.extended(
        onPressed: _generarLlaveDesdeGrupos,
        backgroundColor: Colors.deepPurple,
        icon: const Icon(Icons.account_tree, color: Colors.white),
        label: const Text(
          'Armar Llave',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    return null;
  }

  Widget _buildEncabezado(
    Map<String, dynamic> torneoData,
    String faseActual,
    String formato,
  ) {
    final Map<String, String> etiquetaFase = {
      'inscripcion': 'Inscripción Abierta',
      'grupos': 'Fase de Grupos',
      'llave': 'Llave Eliminatoria',
      'finalizado': 'Finalizado',
    };
    final Map<String, Color> colorFase = {
      'inscripcion': Colors.blue,
      'grupos': Colors.orange,
      'llave': Colors.deepPurple,
      'finalizado': Colors.green,
    };
    final color = colorFase[faseActual] ?? Colors.grey;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${torneoData['categoria'] ?? 'General'} · ${torneoData['rama'] ?? ''} · $formato',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  'Precio: \$${torneoData['precioInscripcion'] ?? 0} por pareja · Cupo: ${torneoData['maxParejas'] ?? '-'}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              etiquetaFase[faseActual] ?? faseActual,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          if (widget.esAdmin && faseActual == 'inscripcion') ...[
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _confirmarYSortear(torneoData),
              icon: const Icon(Icons.casino_rounded, size: 18),
              label: const Text('Sortear'),
              style: OutlinedButton.styleFrom(foregroundColor: _kPrimary),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // TAB: INSCRIPCIONES
  // ==========================================================
  Widget _buildTabInscripciones(String faseActual) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('torneos')
          .doc(widget.torneoId)
          .collection('parejas_inscriptas')
          .orderBy('fechaInscripcion', descending: true)
          .snapshots(),
      builder: (context, subSnapshot) {
        if (!subSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final parejas = subSnapshot.data!.docs;
        if (parejas.isEmpty) {
          return const Center(child: Text('No hay parejas inscriptas aún.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: parejas.length,
          itemBuilder: (context, i) {
            final p = parejas[i].data() as Map<String, dynamic>;
            final j1 = p['jugador1'] ?? {};
            final j2 = p['jugador2'] ?? {};
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.sports_tennis, color: _kPrimary),
                title: Text('${j1['nombreCompleto']} y ${j2['nombreCompleto']}'),
                subtitle: Text(
                  'Tel: ${j1['telefono']} / ${j2['telefono']} | Estado: ${p['estadoPago']}',
                ),
                trailing: Chip(
                  label: Text(
                    p['estadoPago'] == 'pagado' ? 'PAGADO' : 'PENDIENTE',
                    style: TextStyle(
                      color: p['estadoPago'] == 'pagado'
                          ? Colors.green.shade900
                          : Colors.orange.shade900,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: p['estadoPago'] == 'pagado'
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // TAB: GRUPOS (fixture + posiciones por zona)
  // ==========================================================
  Widget _buildTabGrupos(Map<String, dynamic> torneoData) {
    final Map<String, dynamic> gruposRaw = Map<String, dynamic>.from(
      torneoData['grupos'] ?? {},
    );
    final nombresGrupos = gruposRaw.keys.toList()..sort();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('torneos')
          .doc(widget.torneoId)
          .collection('partidos')
          .where('fase', isEqualTo: 'grupos')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final todos = snap.data!.docs
            .map((d) => PartidoTorneo.fromFirestore(d.id, d.data() as Map<String, dynamic>))
            .toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: nombresGrupos.length,
          itemBuilder: (context, i) {
            final nombreGrupo = nombresGrupos[i];
            final parejasDelGrupo = (gruposRaw[nombreGrupo] as List<dynamic>)
                .map(
                  (p) => ParejaSeed(
                    id: p['id'] as String,
                    nombre: p['nombre'] as String,
                  ),
                )
                .toList();
            final partidosDelGrupo = todos
                .where((p) => p.grupoNombre == nombreGrupo)
                .toList()
              ..sort((a, b) => a.ronda.compareTo(b.ronda));
            final posiciones = BracketGeneratorService.calcularPosiciones(
              parejasDelGrupo,
              partidosDelGrupo,
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreGrupo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildTablaPosiciones(posiciones),
                    const SizedBox(height: 14),
                    const Text(
                      'Partidos',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    ...partidosDelGrupo.map((p) => _buildFilaPartido(p)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTablaPosiciones(List<PosicionZona> posiciones) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      children: [
        const TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Pareja', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('PG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Sets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Games', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
            ),
          ],
        ),
        for (int i = 0; i < posiciones.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: i < 2 ? Colors.green.withValues(alpha: 0.06) : null,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${i + 1}. ${posiciones[i].parejaNombre}',
                  style: const TextStyle(fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${posiciones[i].partidosGanados}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${posiciones[i].diferenciaSets >= 0 ? '+' : ''}${posiciones[i].diferenciaSets}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${posiciones[i].diferenciaGames >= 0 ? '+' : ''}${posiciones[i].diferenciaGames}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildFilaPartido(PartidoTorneo p) {
    final jugado = p.estado == 'Jugado';
    return InkWell(
      onTap: widget.esAdmin && p.parejaAId != null && p.parejaBId != null
          ? () => _mostrarDialogoResultado(p)
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: jugado ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${p.parejaANombre}  vs  ${p.parejaBNombre}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: jugado ? FontWeight.normal : FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (jugado)
              Text(
                p.sets.map((s) => '${s.gamesA}-${s.gamesB}').join('  '),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: p.ganador == 'A' ? Colors.blue.shade800 : Colors.red.shade800,
                ),
              )
            else if (widget.esAdmin)
              const Icon(Icons.edit_note_rounded, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // TAB: LLAVE (bracket visual, scroll horizontal por rondas)
  // ==========================================================
  Widget _buildTabLlave() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('torneos')
          .doc(widget.torneoId)
          .collection('partidos')
          .where('fase', isEqualTo: 'llave')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final partidos = snap.data!.docs
            .map((d) => PartidoTorneo.fromFirestore(d.id, d.data() as Map<String, dynamic>))
            .toList();
        if (partidos.isEmpty) {
          return const Center(child: Text('La llave todavía no se armó.'));
        }

        final porRonda = <int, List<PartidoTorneo>>{};
        for (final p in partidos) {
          porRonda.putIfAbsent(p.ronda, () => []).add(p);
        }
        final rondas = porRonda.keys.toList()..sort();
        final maxRonda = rondas.last;

        String nombreRonda(int ronda) {
          final rondasDesdeElFinal = maxRonda - ronda;
          switch (rondasDesdeElFinal) {
            case 0:
              return 'Final';
            case 1:
              return 'Semifinal';
            case 2:
              return 'Cuartos de Final';
            case 3:
              return 'Octavos de Final';
            default:
              return 'Ronda $ronda';
          }
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rondas.map((ronda) {
              final partidosRonda = porRonda[ronda]!
                ..sort((a, b) => a.ordenEnRonda.compareTo(b.ordenEnRonda));
              return Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreRonda(ronda),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _kPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...partidosRonda.map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _buildTarjetaPartidoLlave(p),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildTarjetaPartidoLlave(PartidoTorneo p) {
    final jugado = p.estado == 'Jugado';
    final puedeCargar =
        widget.esAdmin && p.parejaAId != null && p.parejaBId != null && !jugado;

    Widget filaEquipo(String nombre, bool esGanador, int? setsGanados) {
      return Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: esGanador && jugado
            ? Colors.green.withValues(alpha: 0.08)
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                nombre,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: esGanador ? FontWeight.bold : FontWeight.normal,
                  color: nombre == 'A definir' || nombre == 'BYE'
                      ? Colors.grey
                      : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (jugado && setsGanados != null)
              Text(
                '$setsGanados',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  color: esGanador ? Colors.green.shade800 : Colors.grey,
                ),
              ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: puedeCargar ? () => _mostrarDialogoResultado(p) : null,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: puedeCargar
                ? _kPrimary.withValues(alpha: 0.4)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            filaEquipo(p.parejaANombre, p.ganador == 'A', jugado ? p.setsGanadosA : null),
            const Divider(height: 1),
            filaEquipo(p.parejaBNombre, p.ganador == 'B', jugado ? p.setsGanadosB : null),
            if (puedeCargar)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Cargar resultado',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // Diálogo de carga de resultado (mejor de 3 sets)
  // ==========================================================
  void _mostrarDialogoResultado(PartidoTorneo partido) {
    final controllers = List.generate(
      3,
      (_) => [TextEditingController(), TextEditingController()],
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${partido.parejaANombre} vs ${partido.parejaBNombre}'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cargá los games de cada set (dejá vacío un 3er set si no se jugó).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              for (int s = 0; s < 3; s++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 50, child: Text('Set ${s + 1}')),
                      Expanded(
                        child: TextField(
                          controller: controllers[s][0],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('-'),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controllers[s][1],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                    ],
                  ),
                ),
              if (partido.estado == 'Jugado')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        await TorneoFirestoreService.deshacerResultado(
                          torneoId: widget.torneoId,
                          partido: partido,
                        );
                        _snack('Resultado deshecho.');
                      } catch (e) {
                        _snack('Error: $e', esError: true);
                      }
                    },
                    icon: const Icon(Icons.undo, size: 16, color: Colors.red),
                    label: const Text(
                      'Deshacer resultado cargado',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () async {
              final sets = <SetJugado>[];
              for (final par in controllers) {
                final a = int.tryParse(par[0].text.trim());
                final b = int.tryParse(par[1].text.trim());
                if (a != null && b != null) {
                  sets.add(SetJugado(gamesA: a, gamesB: b));
                }
              }
              if (sets.isEmpty) {
                _snack('Cargá al menos un set.', esError: true);
                return;
              }
              Navigator.pop(ctx);
              try {
                await TorneoFirestoreService.registrarResultado(
                  torneoId: widget.torneoId,
                  partido: partido,
                  sets: sets,
                );
                _snack('✅ Resultado cargado.');
              } catch (e) {
                _snack('Error: $e', esError: true);
              }
            },
            child: const Text(
              'Guardar Resultado',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
