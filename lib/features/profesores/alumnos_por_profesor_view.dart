import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profesor_model.dart';

class AlumnosPorProfesorView extends StatefulWidget {
  final ProfesorModel profesor;

  const AlumnosPorProfesorView({super.key, required this.profesor});

  @override
  State<AlumnosPorProfesorView> createState() => _AlumnosPorProfesorViewState();
}

class _AlumnosPorProfesorViewState extends State<AlumnosPorProfesorView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _diaSeleccionado;
  String? _actividadSeleccionada;

  final List<String> _diasSemana = [
    'Todos',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];

  @override
  void initState() {
    super.initState();
    // Si el profe tiene especialidades, seleccionamos la primera por defecto
    if (widget.profesor.especialidades.isNotEmpty) {
      _actividadSeleccionada = widget.profesor.especialidades.first;
    }
  }

  @override
  void didUpdateWidget(covariant AlumnosPorProfesorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profesor.id != widget.profesor.id) {
      setState(() {
        _diaSeleccionado = null;
        _actividadSeleccionada = widget.profesor.especialidades.isNotEmpty
            ? widget.profesor.especialidades.first
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alumnos de ${widget.profesor.nombre}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Especialidades: ${widget.profesor.especialidades.join(", ")}',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Asignar Manual'),
                onPressed: () => _mostrarDialogoAsignacionManual(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filtros por Día y Actividad
          Row(
            children: [
              // Filtro por Actividad / Especialidad
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por Actividad',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  value: _actividadSeleccionada,
                  items: widget.profesor.especialidades
                      .map(
                        (act) => DropdownMenuItem(value: act, child: Text(act)),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _actividadSeleccionada = val),
                ),
              ),
              const SizedBox(width: 16),

              // Filtro por Día de la Semana
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por Día',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  value: _diaSeleccionado ?? 'Todos',
                  items: _diasSemana
                      .map(
                        (dia) => DropdownMenuItem(value: dia, child: Text(dia)),
                      )
                      .toList(),
                  onChanged: (val) => setState(() {
                    _diaSeleccionado = (val == 'Todos') ? null : val;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Lista de Alumnos Filtrados
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('socios').snapshots(),
              builder: (context, socioSnapshot) {
                if (!socioSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('inscripciones')
                      .where('profesorId', isEqualTo: widget.profesor.id)
                      .where('activa', isEqualTo: true)
                      .snapshots(),
                  builder: (context, manualSnapshot) {
                    if (!manualSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final idsManuales = manualSnapshot.data!.docs
                        .map(
                          (doc) =>
                              (doc.data() as Map<String, dynamic>)['socioId']
                                  ?.toString(),
                        )
                        .toSet();

                    final alumnosFiltrados = socioSnapshot.data!.docs.where((
                      doc,
                    ) {
                      final data = doc.data() as Map<String, dynamic>;

                      // Filtro por actividad
                      final deporteSocio = data['deporte'] ?? '';
                      final coincideDeporte =
                          _actividadSeleccionada == null ||
                          deporteSocio == _actividadSeleccionada;

                      // Filtro por día
                      final List<dynamic> diasSocio = data['dias'] ?? [];
                      final coincideDia =
                          _diaSeleccionado == null ||
                          diasSocio.contains(_diaSeleccionado);

                      final esManual = idsManuales.contains(doc.id);

                      return (coincideDeporte && coincideDia) || esManual;
                    }).toList();

                    if (alumnosFiltrados.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay alumnos para los filtros seleccionados.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: alumnosFiltrados.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Color(0xFFF1F5F9)),
                      itemBuilder: (context, index) {
                        final doc = alumnosFiltrados[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final esManual = idsManuales.contains(doc.id);

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: esManual
                                ? Colors.purple.withValues(alpha: 0.1)
                                : Colors.blue.withValues(alpha: 0.1),
                            child: Icon(
                              Icons.school,
                              color: esManual ? Colors.purple : Colors.blue,
                            ),
                          ),
                          title: Text(
                            data['nombre'] ?? 'Socio sin nombre',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            esManual
                                ? 'Asignación Manual'
                                : 'Actividad: ${data['deporte'] ?? 'N/A'} • Días: ${(data['dias'] as List?)?.join(', ') ?? 'Sin día'}',
                          ),
                          trailing: esManual
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () {
                                    final docManual = manualSnapshot.data!.docs
                                        .firstWhere(
                                          (mDoc) =>
                                              (mDoc.data()
                                                  as Map<
                                                    String,
                                                    dynamic
                                                  >)['socioId'] ==
                                              doc.id,
                                        );
                                    _firestore
                                        .collection('inscripciones')
                                        .doc(docManual.id)
                                        .delete();
                                  },
                                )
                              : const Chip(
                                  label: Text(
                                    'Auto',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  backgroundColor: Color(0xFFEFF6FF),
                                  side: BorderSide.none,
                                ),
                        );
                      },
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

  void _mostrarDialogoAsignacionManual(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Asignar Alumno Manualmente'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('socios').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final socios = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: socios.length,
                  itemBuilder: (context, index) {
                    final socioDoc = socios[index];
                    final socioData = socioDoc.data() as Map<String, dynamic>;

                    return ListTile(
                      title: Text(socioData['nombre'] ?? ''),
                      subtitle: Text('DNI: ${socioData['dni'] ?? ''}'),
                      trailing: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.green,
                      ),
                      onTap: () async {
                        await _firestore.collection('inscripciones').add({
                          'socioId': socioDoc.id,
                          'socioNombre': socioData['nombre'],
                          'profesorId': widget.profesor.id,
                          'profesorNombre': widget.profesor.nombre,
                          'activa': true,
                          'fechaInscripcion': Timestamp.now(),
                        });
                        if (context.mounted) Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }
}
