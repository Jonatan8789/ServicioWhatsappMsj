import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'crear_partido_abierto_page.dart';
import 'partido_abierto_model.dart';
import 'partido_abierto_repository.dart';

class PartidosAbiertosPage extends StatefulWidget {
  const PartidosAbiertosPage({super.key});

  @override
  State<PartidosAbiertosPage> createState() => _PartidosAbiertosPageState();
}

class _PartidosAbiertosPageState extends State<PartidosAbiertosPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _filtroCategoria = 'Todas';
  Map<String, dynamic>? _datosSocio;
  String? _socioDocId;

  @override
  void initState() {
    super.initState();
    _cargarSocio();
  }

  Future<void> _cargarSocio() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // 🚨 El id del doc 'socios/{id}' no es el uid de Auth, ver el mismo
    // fix en reserva_cancha_screen.dart — buscar por 'usuarioUid'.
    final query = await _firestore
        .collection('socios')
        .where('usuarioUid', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty && mounted) {
      setState(() {
        _socioDocId = query.docs.first.id;
        _datosSocio = query.docs.first.data();
      });
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _unirme(PartidoAbiertoModel partido) async {
    if (_socioDocId == null) {
      _snack(
        'No encontramos tu ficha de socio. Contactá a administración.',
        Colors.red,
      );
      return;
    }
    final String nombreSocio = _datosSocio != null
        ? '${_datosSocio!['nombre'] ?? ''} ${_datosSocio!['apellido'] ?? ''}'
              .trim()
        : 'Socio';

    try {
      await unirseAPartidoAtomica(
        firestore: _firestore,
        partidoId: partido.id,
        jugadorId: _socioDocId!,
        jugadorNombre: nombreSocio,
      );
      _snack(
        '🎾 ¡Listo! Te anotaste. Tu parte se cobrará en caja.',
        Colors.green,
      );
    } on PartidoCompletoException {
      _snack('Justo se completó. Probá con otro partido.', Colors.red);
    } on YaAnotadoEnPartidoException {
      _snack('Ya estabas anotado en ese partido.', Colors.orange);
    } on PartidoNoDisponibleException {
      _snack('Ese partido ya no está disponible.', Colors.red);
    } catch (e) {
      _snack('Error: $e', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final socioDocId = _socioDocId;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Partidos Abiertos'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CrearPartidoAbiertoPage(),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Crear partido'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('Categoría: '),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _filtroCategoria,
                    items: ['Todas', ...categoriasPartidoAbierto]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _filtroCategoria = v ?? 'Todas'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Un solo filtro de igualdad (estado) para que indexe
              // automático; la fecha futura y la categoría se filtran en
              // memoria, ya que 'partidos_abiertos' no es una colección de
              // alto volumen (sólo los que alguien decide abrir).
              stream: _firestore
                  .collection('partidos_abiertos')
                  .where('estado', isEqualTo: 'Abierto')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final hoy = DateTime.now();
                final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);

                final partidos = snapshot.data!.docs
                    .map(
                      (d) => PartidoAbiertoModel.fromFirestore(
                        d.id,
                        d.data() as Map<String, dynamic>,
                      ),
                    )
                    .where((p) {
                      final fechaDia = DateTime(
                        p.fecha.year,
                        p.fecha.month,
                        p.fecha.day,
                      );
                      if (fechaDia.isBefore(hoyDia)) return false;
                      if (_filtroCategoria != 'Todas' &&
                          p.categoria != _filtroCategoria) {
                        return false;
                      }
                      return true;
                    })
                    .toList()
                  ..sort((a, b) {
                    final c = a.fecha.compareTo(b.fecha);
                    return c != 0
                        ? c
                        : a.horaInicio.compareTo(b.horaInicio);
                  });

                if (partidos.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No hay partidos abiertos por ahora.\n'
                        '¡Creá uno vos!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: partidos.length,
                  itemBuilder: (context, i) {
                    final p = partidos[i];
                    final yaAnotado =
                        socioDocId != null &&
                        p.jugadoresIds.contains(socioDocId);
                    final lugares =
                        PartidoAbiertoModel.cupoJugadores -
                        p.jugadoresIds.length;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  p.cancha,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Chip(label: Text(p.categoria)),
                              ],
                            ),
                            Text(
                              '${p.fecha.day}/${p.fecha.month}/${p.fecha.year} · '
                              '${p.horaInicio.toString().padLeft(2, '0')}:00 hs',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Jugadores: ${p.jugadoresNombres.join(', ')}',
                            ),
                            Text(
                              'Faltan $lugares · Tu parte: \$${p.montoPorJugador.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: yaAnotado
                                      ? Colors.grey
                                      : const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: yaAnotado
                                    ? null
                                    : () => _unirme(p),
                                child: Text(
                                  yaAnotado ? 'Ya estás anotado' : 'Unirme',
                                ),
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
        ],
      ),
    );
  }
}
