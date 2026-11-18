import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'padel_score_engine.dart';

const _kFondoOscuro = Color(0xFF0F172A);

/// Modal de pre-partido: arma los dos equipos (socio buscado por DNI o
/// invitado con texto libre), elige modo de juego y cantidad de sets, y
/// escribe el documento activo en `partidos_marcador/{idCancha}` para que
/// el mando auxiliar y la TV de cancha empiecen a sincronizar en vivo.
class SetupPartidoDialog extends StatefulWidget {
  final String canchaNombre;

  const SetupPartidoDialog({super.key, required this.canchaNombre});

  @override
  State<SetupPartidoDialog> createState() => _SetupPartidoDialogState();
}

class _SetupPartidoDialogState extends State<SetupPartidoDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  late final List<_JugadorFormState> _equipoA;
  late final List<_JugadorFormState> _equipoB;

  final _nombreEquipoACtrl = TextEditingController(text: 'Pareja 1');
  final _nombreEquipoBCtrl = TextEditingController(text: 'Pareja 2');

  String _modoJuego = PadelScoreEngine.modoPuntoDeOro;
  int _cantidadSets = 3;
  String _saqueInicial = 'A';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _equipoA = [_JugadorFormState(), _JugadorFormState()];
    _equipoB = [_JugadorFormState(), _JugadorFormState()];
  }

  @override
  void dispose() {
    _nombreEquipoACtrl.dispose();
    _nombreEquipoBCtrl.dispose();
    for (final j in [..._equipoA, ..._equipoB]) {
      j.dispose();
    }
    super.dispose();
  }

  Future<void> _buscarSocioPorDni(_JugadorFormState jugador) async {
    final dniLimpio = jugador.dniCtrl.text.trim().replaceAll(
      RegExp(r'\D'),
      '',
    );
    if (dniLimpio.isEmpty) return;

    setState(() => jugador.buscando = true);
    try {
      QuerySnapshot query = await _firestore
          .collection('socios')
          .where('dni', isEqualTo: dniLimpio)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        final dniNumerico = int.tryParse(dniLimpio);
        if (dniNumerico != null) {
          query = await _firestore
              .collection('socios')
              .where('dni', isEqualTo: dniNumerico)
              .limit(1)
              .get();
        }
      }

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data() as Map<String, dynamic>;
        final String nombreCompleto = (data['nombreCompleto'] ?? '')
            .toString()
            .trim()
            .isNotEmpty
            ? data['nombreCompleto'].toString().trim()
            : "${data['nombre'] ?? ''} ${data['apellido'] ?? ''}".trim();

        setState(() {
          jugador.nombreCtrl.text = nombreCompleto.isEmpty
              ? 'Socio sin nombre'
              : nombreCompleto;
          jugador.fotoUrl =
              (data['fotoUrl'] ?? data['fotoPerfil'] ?? '').toString();
          jugador.socioId = query.docs.first.id;
          jugador.esSocio = true;
        });
      } else {
        setState(() {
          jugador.esSocio = false;
          jugador.socioId = null;
          jugador.fotoUrl = '';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se encontró ningún socio con ese DNI.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error buscando socio: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => jugador.buscando = false);
    }
  }

  Map<String, dynamic> _armarEquipo(
    TextEditingController nombreEquipoCtrl,
    List<_JugadorFormState> jugadores,
  ) {
    return {
      'nombre': nombreEquipoCtrl.text.trim(),
      'jugadores': jugadores
          .map(
            (j) => {
              'nombre': j.nombreCtrl.text.trim(),
              'fotoUrl': j.fotoUrl,
              'socioId': j.socioId,
            },
          )
          .toList(),
    };
  }

  Future<void> _iniciarPartido() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    try {
      final idCancha = PadelScoreEngine.idDocumentoDesdeCancha(
        widget.canchaNombre,
      );
      final estado = PadelScoreEngine.estadoInicial(
        cancha: widget.canchaNombre,
        equipoA: _armarEquipo(_nombreEquipoACtrl, _equipoA),
        equipoB: _armarEquipo(_nombreEquipoBCtrl, _equipoB),
        modoJuego: _modoJuego,
        cantidadSets: _cantidadSets,
        saqueInicial: _saqueInicial,
      );

      await _firestore
          .collection('partidos_marcador')
          .doc(idCancha)
          .set(estado);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar el partido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildFormularioJugador(_JugadorFormState jugador, String etiqueta) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: TextFormField(
                  controller: jugador.dniCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'DNI',
                    isDense: true,
                    suffixIcon: jugador.buscando
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search, size: 18),
                            onPressed: () => _buscarSocioPorDni(jugador),
                          ),
                  ),
                  onChanged: (v) {
                    if (v.replaceAll(RegExp(r'\D'), '').length >= 7) {
                      _buscarSocioPorDni(jugador);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: jugador.nombreCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nombre del Jugador',
                    isDense: true,
                    suffixIcon: jugador.esSocio
                        ? const Icon(
                            Icons.verified,
                            color: Colors.green,
                            size: 18,
                          )
                        : null,
                  ),
                  onChanged: (_) {
                    if (jugador.esSocio) {
                      setState(() {
                        jugador.esSocio = false;
                        jugador.socioId = null;
                        jugador.fotoUrl = '';
                      });
                    }
                  },
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetaEquipo({
    required String titulo,
    required Color color,
    required TextEditingController nombreEquipoCtrl,
    required List<_JugadorFormState> jugadores,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: nombreEquipoCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre del Equipo / Pareja',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          _buildFormularioJugador(jugadores[0], 'Jugador 1'),
          _buildFormularioJugador(jugadores[1], 'Jugador 2'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configurar Partido',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            widget.canchaNombre,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool angosto = constraints.maxWidth < 480;
                    final equipoA = _buildTarjetaEquipo(
                      titulo: 'Equipo A',
                      color: Colors.blue,
                      nombreEquipoCtrl: _nombreEquipoACtrl,
                      jugadores: _equipoA,
                    );
                    final equipoB = _buildTarjetaEquipo(
                      titulo: 'Equipo B',
                      color: Colors.red,
                      nombreEquipoCtrl: _nombreEquipoBCtrl,
                      jugadores: _equipoB,
                    );
                    if (angosto) {
                      return Column(
                        children: [
                          equipoA,
                          const SizedBox(height: 12),
                          equipoB,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: equipoA),
                        const SizedBox(width: 12),
                        Expanded(child: equipoB),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _modoJuego,
                  decoration: const InputDecoration(
                    labelText: 'Modalidad de Juego (en 40 iguales)',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: PadelScoreEngine.modoPuntoDeOro,
                      child: Text('Punto de Oro (muerte súbita)'),
                    ),
                    DropdownMenuItem(
                      value: PadelScoreEngine.modoVentaja,
                      child: Text('Ventaja Tradicional'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _modoJuego = v ?? PadelScoreEngine.modoPuntoDeOro),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _cantidadSets,
                  decoration: const InputDecoration(
                    labelText: 'Formato del Partido',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Set Único')),
                    DropdownMenuItem(value: 3, child: Text('Mejor de 3 Sets')),
                    DropdownMenuItem(value: 5, child: Text('Mejor de 5 Sets')),
                  ],
                  onChanged: (v) => setState(() => _cantidadSets = v ?? 3),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _saqueInicial,
                  decoration: const InputDecoration(
                    labelText: 'Saque Inicial',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'A', child: Text('Equipo A')),
                    DropdownMenuItem(value: 'B', child: Text('Equipo B')),
                  ],
                  onChanged: (v) => setState(() => _saqueInicial = v ?? 'A'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kFondoOscuro,
            foregroundColor: Colors.white,
          ),
          onPressed: _guardando ? null : _iniciarPartido,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Iniciar Partido'),
        ),
      ],
    );
  }
}

class _JugadorFormState {
  final dniCtrl = TextEditingController();
  final nombreCtrl = TextEditingController();
  String fotoUrl = '';
  String? socioId;
  bool esSocio = false;
  bool buscando = false;

  void dispose() {
    dniCtrl.dispose();
    nombreCtrl.dispose();
  }
}
