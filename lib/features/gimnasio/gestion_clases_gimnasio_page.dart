import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'clase_gimnasio_model.dart';
import 'clase_gimnasio_repository.dart';

class GestionClasesGimnasioPage extends StatefulWidget {
  const GestionClasesGimnasioPage({super.key});

  @override
  State<GestionClasesGimnasioPage> createState() =>
      _GestionClasesGimnasioPageState();
}

class _GestionClasesGimnasioPageState
    extends State<GestionClasesGimnasioPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime _fechaSeleccionada = DateTime.now();

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _crearClase() async {
    final nombreCtrl = TextEditingController();
    final profesorCtrl = TextEditingController();
    final cupoCtrl = TextEditingController(text: '12');
    int horaSeleccionada = 9;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Nueva clase'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre (ej. Spinning, Funcional)',
                  ),
                ),
                TextField(
                  controller: profesorCtrl,
                  decoration: const InputDecoration(labelText: 'Profesor'),
                ),
                TextField(
                  controller: cupoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cupo máximo'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: horaSeleccionada,
                  decoration: const InputDecoration(labelText: 'Horario'),
                  items: List.generate(16, (i) => 6 + i)
                      .map(
                        (h) => DropdownMenuItem(
                          value: h,
                          child: Text('${h.toString().padLeft(2, '0')}:00 hs'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setModalState(() => horaSeleccionada = v ?? 9),
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
                if (nombreCtrl.text.trim().isEmpty) return;
                final clase = ClaseGimnasioModel(
                  id: 'sin-usar',
                  nombre: nombreCtrl.text.trim(),
                  profesorNombre: profesorCtrl.text.trim(),
                  fecha: _fechaSeleccionada,
                  horaInicio: horaSeleccionada,
                  cupoMaximo: int.tryParse(cupoCtrl.text) ?? 12,
                );
                await _firestore.collection('clases_gimnasio').add(
                  clase.toFirestore(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('✅ Clase creada.', Colors.green);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _quitarSocio(ClaseGimnasioModel clase, String socioId) async {
    await cancelarInscripcionClaseAtomica(
      firestore: _firestore,
      claseId: clase.id,
      socioId: socioId,
    );
    _snack('Socio dado de baja de la clase.', Colors.orange);
  }

  @override
  Widget build(BuildContext context) {
    final inicioDia = DateTime(
      _fechaSeleccionada.year,
      _fechaSeleccionada.month,
      _fechaSeleccionada.day,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Clases del Gimnasio'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearClase,
        icon: const Icon(Icons.add),
        label: const Text('Nueva clase'),
      ),
      body: Column(
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
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                    );
                    if (picked != null) {
                      setState(() => _fechaSeleccionada = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('clases_gimnasio')
                  .where(
                    'fecha',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia),
                  )
                  .where(
                    'fecha',
                    isLessThan: Timestamp.fromDate(
                      inicioDia.add(const Duration(days: 1)),
                    ),
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final clases = snapshot.data!.docs
                    .map(
                      (d) => ClaseGimnasioModel.fromFirestore(
                        d.id,
                        d.data() as Map<String, dynamic>,
                      ),
                    )
                    .toList()
                  ..sort((a, b) => a.horaInicio.compareTo(b.horaInicio));

                if (clases.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay clases creadas para este día.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: clases.length,
                  itemBuilder: (context, i) {
                    final c = clases[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(
                          '${c.nombre} · ${c.horaInicio.toString().padLeft(2, '0')}:00 hs',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${c.profesorNombre} · ${c.inscriptosIds.length}/${c.cupoMaximo} '
                          '${c.listaEsperaIds.isNotEmpty ? '· ${c.listaEsperaIds.length} en espera' : ''}',
                        ),
                        children: [
                          if (c.inscriptosNombres.isEmpty &&
                              c.listaEsperaNombres.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Sin inscriptos todavía.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ...List.generate(c.inscriptosIds.length, (idx) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              title: Text(c.inscriptosNombres[idx]),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    _quitarSocio(c, c.inscriptosIds[idx]),
                              ),
                            );
                          }),
                          ...List.generate(c.listaEsperaIds.length, (idx) {
                            return ListTile(
                              dense: true,
                              leading: Text('#${idx + 1}'),
                              title: Text(c.listaEsperaNombres[idx]),
                              subtitle: const Text(
                                'En lista de espera',
                                style: TextStyle(fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    _quitarSocio(c, c.listaEsperaIds[idx]),
                              ),
                            );
                          }),
                        ],
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
