import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../profesores/profesor_model.dart';
import 'cancha_padel_repository.dart';

const List<String> _nombresDias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// Administración de turnos fijos: turnos de cancha (abonos a nombre de un
/// socio) y clases recurrentes (con profesor, cupo y cobro por alumno) —
/// antes esto vivía mezclado dentro de canchas_page.dart, sólo para
/// turnos de cancha y sin forma de armar clases recurrentes.
class TurnosFijosPadelPage extends StatefulWidget {
  const TurnosFijosPadelPage({super.key});

  @override
  State<TurnosFijosPadelPage> createState() => _TurnosFijosPadelPageState();
}

class _TurnosFijosPadelPageState extends State<TurnosFijosPadelPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TabController _tabController;

  List<QueryDocumentSnapshot> _todosLosSocios = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarSocios();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarSocios() async {
    final snap = await _firestore.collection('socios').get();
    if (mounted) setState(() => _todosLosSocios = snap.docs);
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ---------------------------------------------------------------------
  // Turnos fijos de cancha
  // ---------------------------------------------------------------------

  Future<void> _nuevoTurnoFijoCancha() async {
    final canchas = await obtenerNombresCanchasActivas(_firestore);
    if (!mounted) return;
    if (canchas.isEmpty) {
      _snack('⚠️ No hay ninguna cancha configurada.', Colors.orange);
      return;
    }

    String busquedaSocio = '';
    Map<String, dynamic>? socioSel;
    String? socioIdSel;
    String canchaSel = canchas.first;
    int diaSel = 1;
    int horaSel = 18;
    int duracionSel = 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final coincidencias = busquedaSocio.trim().isEmpty
              ? const <QueryDocumentSnapshot>[]
              : _todosLosSocios.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final nombreCompleto =
                      '${d['nombre'] ?? ''} ${d['apellido'] ?? ''}'
                          .toLowerCase();
                  return nombreCompleto.contains(busquedaSocio.toLowerCase());
                }).take(5).toList();

          return AlertDialog(
            title: const Text('Nuevo turno fijo de cancha'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar socio',
                    ),
                    onChanged: (v) => setModalState(() => busquedaSocio = v),
                  ),
                  if (socioSel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Chip(
                        label: Text(
                          '${socioSel!['nombre']} ${socioSel!['apellido']}',
                        ),
                        onDeleted: () => setModalState(() {
                          socioSel = null;
                          socioIdSel = null;
                        }),
                      ),
                    )
                  else
                    ...coincidencias.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      return ListTile(
                        dense: true,
                        title: Text('${d['nombre']} ${d['apellido']}'),
                        onTap: () => setModalState(() {
                          socioSel = d;
                          socioIdSel = doc.id;
                          busquedaSocio = '';
                        }),
                      );
                    }),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: canchaSel,
                    decoration: const InputDecoration(labelText: 'Cancha'),
                    items: canchas
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setModalState(() => canchaSel = v ?? canchaSel),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: diaSel,
                    decoration: const InputDecoration(
                      labelText: 'Día de la semana',
                    ),
                    items: List.generate(
                      7,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text(_nombresDias[i]),
                      ),
                    ),
                    onChanged: (v) => setModalState(() => diaSel = v ?? diaSel),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: horaSel,
                          decoration: const InputDecoration(labelText: 'Hora'),
                          items: List.generate(16, (i) => 7 + i)
                              .map(
                                (h) => DropdownMenuItem(
                                  value: h,
                                  child: Text('${h.toString().padLeft(2, '0')}:00'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setModalState(() => horaSel = v ?? horaSel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: duracionSel,
                          decoration: const InputDecoration(
                            labelText: 'Duración',
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 hora')),
                            DropdownMenuItem(value: 2, child: Text('2 horas')),
                          ],
                          onChanged: (v) => setModalState(
                            () => duracionSel = v ?? duracionSel,
                          ),
                        ),
                      ),
                    ],
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
                onPressed: () async {
                  if (socioIdSel == null) {
                    _snack('Elegí un socio de la lista.', Colors.orange);
                    return;
                  }
                  Navigator.pop(ctx);
                  final nombreFinal =
                      '${socioSel!['nombre'] ?? ''} ${socioSel!['apellido'] ?? ''}'
                          .trim();
                  try {
                    final resp = await FirebaseFunctions.instance
                        .httpsCallable('crearTurnoRecurrenteCanchaStaff')
                        .call({
                          'socioId': socioIdSel,
                          'nombreCliente': nombreFinal,
                          'cancha': canchaSel,
                          'diaSemana': diaSel,
                          'horaInicio': horaSel,
                          'duracionHoras': duracionSel,
                        });
                    if (resp.data['success'] == true) {
                      _snack('Turno fijo asignado a $nombreFinal.', Colors.green);
                    } else {
                      _snack(
                        resp.data['error'] ?? 'No se pudo asignar el turno fijo.',
                        Colors.red,
                      );
                    }
                  } catch (e) {
                    _snack('Error: $e', Colors.red);
                  }
                },
                child: const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _cancelarTurnoFijoCancha(String turnoId) async {
    try {
      final resp = await FirebaseFunctions.instance
          .httpsCallable('cancelarTurnoRecurrenteCancha')
          .call({'turnoId': turnoId});
      _snack(
        'Turno fijo cancelado (${resp.data['semanasLiberadas'] ?? 0} semana/s liberada/s).',
        Colors.orange,
      );
    } catch (e) {
      _snack('Error: $e', Colors.red);
    }
  }

  Widget _buildTabTurnosCancha() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _nuevoTurnoFijoCancha,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo turno fijo de cancha'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('turnos_recurrentes_canchas')
                .where('activo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay turnos fijos de cancha activos.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final dia =
                      _nombresDias[((d['diaSemana'] as num?)?.toInt() ?? 1) - 1];
                  return Card(
                    child: ListTile(
                      title: Text(d['nombreCliente']?.toString() ?? '-'),
                      subtitle: Text(
                        '$dia ${d['horaInicio']}:00hs · ${d['cancha']} · \$${d['precio']}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Cancelar turno fijo',
                        onPressed: () => _cancelarTurnoFijoCancha(docs[i].id),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Clases recurrentes
  // ---------------------------------------------------------------------

  Future<void> _nuevaClaseRecurrente() async {
    final profesoresSnap = await _firestore
        .collection('profesores')
        .where('especialidades', arrayContains: 'Pádel')
        .where('activo', isEqualTo: true)
        .get();
    final profesores = profesoresSnap.docs
        .map((d) => ProfesorModel.fromFirestore(d.id, d.data()))
        .toList();
    final canchas = await obtenerNombresCanchasActivas(_firestore);

    if (!mounted) return;
    if (profesores.isEmpty) {
      _snack(
        '⚠️ No hay ningún profesor con la especialidad "Pádel" activo.',
        Colors.orange,
      );
      return;
    }
    if (canchas.isEmpty) {
      _snack('⚠️ No hay ninguna cancha configurada.', Colors.orange);
      return;
    }

    final nombreCtrl = TextEditingController(text: 'Clase de Pádel');
    final cupoCtrl = TextEditingController(text: '4');
    final precioCtrl = TextEditingController(text: '3000');
    ProfesorModel profesorSel = profesores.first;
    String canchaSel = canchas.first;
    int diaSel = 1;
    int horaSel = 18;
    int duracionSel = 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Nueva clase recurrente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ProfesorModel>(
                  initialValue: profesorSel,
                  decoration: const InputDecoration(labelText: 'Profesor'),
                  items: profesores
                      .map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.nombre)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setModalState(() => profesorSel = v ?? profesorSel),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: canchaSel,
                  decoration: const InputDecoration(labelText: 'Cancha'),
                  items: canchas
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) =>
                      setModalState(() => canchaSel = v ?? canchaSel),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: diaSel,
                  decoration: const InputDecoration(
                    labelText: 'Día de la semana',
                  ),
                  items: List.generate(
                    7,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(_nombresDias[i]),
                    ),
                  ),
                  onChanged: (v) => setModalState(() => diaSel = v ?? diaSel),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: horaSel,
                        decoration: const InputDecoration(labelText: 'Hora'),
                        items: List.generate(16, (i) => 7 + i)
                            .map(
                              (h) => DropdownMenuItem(
                                value: h,
                                child: Text('${h.toString().padLeft(2, '0')}:00'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setModalState(() => horaSel = v ?? horaSel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: duracionSel,
                        decoration: const InputDecoration(
                          labelText: 'Duración',
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 hora')),
                          DropdownMenuItem(value: 2, child: Text('2 horas')),
                        ],
                        onChanged: (v) =>
                            setModalState(() => duracionSel = v ?? duracionSel),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cupoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cupo máximo',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: precioCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Precio por alumno',
                          prefixText: '\$ ',
                        ),
                      ),
                    ),
                  ],
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
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final resp = await FirebaseFunctions.instance
                      .httpsCallable('crearTurnoRecurrenteClasePadelStaff')
                      .call({
                        'profesorId': profesorSel.id,
                        'profesorNombre': profesorSel.nombre,
                        'nombreClase': nombreCtrl.text.trim(),
                        'cancha': canchaSel,
                        'diaSemana': diaSel,
                        'horaInicio': horaSel,
                        'duracionHoras': duracionSel,
                        'cupoMaximo': int.tryParse(cupoCtrl.text) ?? 4,
                        'precioPorAlumno': double.tryParse(precioCtrl.text) ?? 0,
                      });
                  if (resp.data['success'] == true) {
                    _snack('Clase recurrente creada.', Colors.green);
                  } else {
                    _snack(
                      resp.data['error'] ?? 'No se pudo crear la clase recurrente.',
                      Colors.red,
                    );
                  }
                } catch (e) {
                  _snack('Error: $e', Colors.red);
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelarClaseRecurrente(String turnoId) async {
    try {
      final resp = await FirebaseFunctions.instance
          .httpsCallable('cancelarTurnoRecurrenteClasePadel')
          .call({'turnoId': turnoId});
      if (resp.data['success'] != true) {
        _snack(resp.data['error'] ?? 'No se pudo cancelar.', Colors.red);
        return;
      }
      final clasesConAlumnos = (resp.data['clasesConAlumnos'] as List?) ?? [];
      _snack(
        'Clase recurrente cancelada (${resp.data['semanasLiberadas'] ?? 0} ocurrencia/s liberada/s).',
        Colors.orange,
      );
      if (clasesConAlumnos.isNotEmpty && mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('⚠️ Hay ocurrencias con alumnos anotados'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Estas ocurrencias futuras ya tienen alumnos anotados y '
                    'NO se cancelaron automáticamente. Avisales y cancelalas '
                    'a mano desde "Clases de Pádel" si corresponde:',
                  ),
                  const SizedBox(height: 8),
                  ...clasesConAlumnos.map(
                    (c) => Text(
                      '• ${c['fecha']}: ${c['inscriptos']} inscripto/s'
                      '${(c['enEspera'] ?? 0) > 0 ? ', ${c['enEspera']} en espera' : ''}',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _snack('Error: $e', Colors.red);
    }
  }

  Widget _buildTabClasesRecurrentes() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _nuevaClaseRecurrente,
              icon: const Icon(Icons.add),
              label: const Text('Nueva clase recurrente'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('turnos_recurrentes_clases_padel')
                .where('activo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No hay clases recurrentes activas.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final dia =
                      _nombresDias[((d['diaSemana'] as num?)?.toInt() ?? 1) - 1];
                  return Card(
                    child: ListTile(
                      title: Text(d['nombreClase']?.toString() ?? 'Clase de Pádel'),
                      subtitle: Text(
                        '$dia ${d['horaInicio']}:00hs · ${d['cancha']} · '
                        '${d['profesorNombre']} · cupo ${d['cupoMaximo']} · '
                        '\$${d['precioPorAlumno']}/alumno',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Cancelar clase recurrente',
                        onPressed: () => _cancelarClaseRecurrente(docs[i].id),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Turnos Fijos'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Turnos fijos de cancha'),
            Tab(text: 'Clases recurrentes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildTabTurnosCancha(), _buildTabClasesRecurrentes()],
      ),
    );
  }
}
