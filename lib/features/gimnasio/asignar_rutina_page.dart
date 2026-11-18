import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'rutina_model.dart';

class AsignarRutinaPage extends StatefulWidget {
  const AsignarRutinaPage({super.key});

  @override
  State<AsignarRutinaPage> createState() => _AsignarRutinaPageState();
}

class _AsignarRutinaPageState extends State<AsignarRutinaPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<QueryDocumentSnapshot> _todosLosSocios = [];
  bool _cargandoSocios = true;
  String _busqueda = '';

  Map<String, dynamic>? _socioElegido;
  String? _socioIdElegido;
  List<EjercicioRutina> _ejercicios = [];
  final _notasCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarSocios();
  }

  Future<void> _cargarSocios() async {
    final snap = await _firestore
        .collection('socios')
        .where('activo', isEqualTo: true)
        .get();
    if (mounted) {
      setState(() {
        _todosLosSocios = snap.docs;
        _cargandoSocios = false;
      });
    }
  }

  Future<void> _elegirSocio(String id, Map<String, dynamic> data) async {
    setState(() {
      _socioIdElegido = id;
      _socioElegido = data;
      _ejercicios = [];
      _notasCtrl.clear();
    });
    final rutinaDoc = await _firestore
        .collection('rutinas_gimnasio')
        .doc(id)
        .get();
    if (rutinaDoc.exists && mounted) {
      final rutina = RutinaModel.fromFirestore(id, rutinaDoc.data()!);
      setState(() {
        _ejercicios = rutina.ejercicios;
        _notasCtrl.text = rutina.notas;
      });
    }
  }

  void _agregarEjercicio() {
    final nombreCtrl = TextEditingController();
    final seriesCtrl = TextEditingController(text: '3');
    final repsCtrl = TextEditingController(text: '12');
    final descansoCtrl = TextEditingController(text: '60');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar ejercicio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Ejercicio'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: seriesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Series'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: repsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Reps'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: descansoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Descanso (s)',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nombreCtrl.text.trim().isEmpty) return;
              setState(() {
                _ejercicios.add(
                  EjercicioRutina(
                    nombre: nombreCtrl.text.trim(),
                    series: int.tryParse(seriesCtrl.text) ?? 3,
                    repeticiones: int.tryParse(repsCtrl.text) ?? 12,
                    descansoSegundos: int.tryParse(descansoCtrl.text) ?? 60,
                  ),
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarRutina() async {
    if (_socioIdElegido == null) return;
    setState(() => _guardando = true);
    try {
      final rutina = RutinaModel(
        socioId: _socioIdElegido!,
        ejercicios: _ejercicios,
        asignadoPorNombre: 'Staff / Profesor',
        fechaAsignacion: DateTime.now(),
        notas: _notasCtrl.text.trim(),
      );
      await _firestore
          .collection('rutinas_gimnasio')
          .doc(_socioIdElegido)
          .set(rutina.toFirestore());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Rutina guardada.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Asignar Rutina'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_socioElegido == null) ...[
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar socio (nombre o DNI)',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
              ),
              const SizedBox(height: 12),
              if (_busqueda.length >= 3)
                Expanded(
                  child: _cargandoSocios
                      ? const Center(child: CircularProgressIndicator())
                      : Builder(
                          builder: (_) {
                            final filtrados = _todosLosSocios.where((doc) {
                              final d = doc.data() as Map<String, dynamic>;
                              final nombre = (d['nombre'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              final dni = (d['dni'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              return nombre.contains(_busqueda) ||
                                  dni.contains(_busqueda);
                            }).toList();
                            return ListView.builder(
                              itemCount: filtrados.length,
                              itemBuilder: (context, i) {
                                final doc = filtrados[i];
                                final d = doc.data() as Map<String, dynamic>;
                                return ListTile(
                                  title: Text(d['nombre'] ?? ''),
                                  subtitle: Text('DNI: ${d['dni'] ?? 'S/D'}'),
                                  onTap: () => _elegirSocio(doc.id, d),
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
                  leading: const Icon(Icons.check_circle, color: Colors.blue),
                  title: Text(_socioElegido!['nombre'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() {
                      _socioElegido = null;
                      _socioIdElegido = null;
                      _ejercicios = [];
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Ejercicios',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextButton.icon(
                    onPressed: _agregarEjercicio,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              Expanded(
                child: _ejercicios.isEmpty
                    ? const Center(
                        child: Text(
                          'Todavía no hay ejercicios cargados.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _ejercicios.length,
                        itemBuilder: (context, i) {
                          final e = _ejercicios[i];
                          return ListTile(
                            leading: const Icon(Icons.fitness_center),
                            title: Text(e.nombre),
                            subtitle: Text(
                              '${e.series} series x ${e.repeticiones} reps · '
                              'Descanso ${e.descansoSegundos}s',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () =>
                                  setState(() => _ejercicios.removeAt(i)),
                            ),
                          );
                        },
                      ),
              ),
              TextField(
                controller: _notasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notas para el socio (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _guardando ? null : _guardarRutina,
                  child: _guardando
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Guardar Rutina'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
