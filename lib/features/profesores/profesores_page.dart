import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profesor_model.dart';
import 'alumnos_por_profesor_view.dart';

class ProfesoresPage extends StatefulWidget {
  final bool esAdmin;
  final String? idProfesorLogueado; // Requerido si esAdmin es false

  const ProfesoresPage({
    super.key,
    required this.esAdmin,
    this.idProfesorLogueado,
  });

  @override
  State<ProfesoresPage> createState() => _ProfesoresPageState();
}

class _ProfesoresPageState extends State<ProfesoresPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _dniController = TextEditingController();
  final _telefonoController = TextEditingController();

  List<String> _deportesDisponibles = [];
  final List<String> _especialidadesSeleccionadas = [];
  String? _idProfesorEditando;
  bool _cargando = true;

  ProfesorModel? _profesorSeleccionado;

  @override
  void initState() {
    super.initState();
    _cargarDeportesYPerfil();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _dniController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  Future<void> _cargarDeportesYPerfil() async {
    try {
      final db = FirebaseFirestore.instance;

      // Cargar lista de deportes
      final docDeportes = await db
          .collection('configuracion')
          .doc('deportes')
          .get();
      if (docDeportes.exists) {
        _deportesDisponibles = List<String>.from(
          docDeportes.data()?['lista'] ?? [],
        );
      }

      // Si el usuario es Profesor (no admin), cargamos directamente su perfil
      if (!widget.esAdmin && widget.idProfesorLogueado != null) {
        final profeDoc = await db
            .collection('profesores')
            .doc(widget.idProfesorLogueado)
            .get();
        if (profeDoc.exists) {
          _profesorSeleccionado = ProfesorModel.fromFirestore(
            profeDoc.id,
            profeDoc.data()!,
          );
        }
      }

      setState(() => _cargando = false);
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _guardarProfesor() async {
    if (!_formKey.currentState!.validate()) return;
    if (_especialidadesSeleccionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos una especialidad.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final db = FirebaseFirestore.instance.collection('profesores');
      final datosProfesor = ProfesorModel(
        id: _idProfesorEditando ?? '',
        nombre: _nombreController.text.trim(),
        dni: _dniController.text.trim(),
        telefono: _telefonoController.text.trim(),
        especialidades: List<String>.from(_especialidadesSeleccionadas),
        activo: true,
      );

      if (_idProfesorEditando == null) {
        await db.add(datosProfesor.toFirestore());
      } else {
        await db.doc(_idProfesorEditando).update(datosProfesor.toFirestore());
      }

      _limpiarFormulario();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Profesor guardado con éxito!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _prepararEdicion(ProfesorModel profe) {
    setState(() {
      _idProfesorEditando = profe.id;
      _nombreController.text = profe.nombre;
      _dniController.text = profe.dni;
      _telefonoController.text = profe.telefono;
      _especialidadesSeleccionadas.clear();
      _especialidadesSeleccionadas.addAll(profe.especialidades);
    });
  }

  void _limpiarFormulario() {
    setState(() {
      _idProfesorEditando = null;
      _nombreController.clear();
      _dniController.clear();
      _telefonoController.clear();
      _especialidadesSeleccionadas.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // VISTA PARA PROFESORES (No Administradores)
    if (!widget.esAdmin) {
      if (_profesorSeleccionado == null) {
        return const Scaffold(
          body: Center(
            child: Text('No se encontró la información del profesor.'),
          ),
        );
      }
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Padding(
          padding: const EdgeInsets.all(32.0),
          child: AlumnosPorProfesorView(profesor: _profesorSeleccionado!),
        ),
      );
    }

    // VISTA PARA ADMINISTRADORES
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // COLUMNA IZQUIERDA: Formulario de Alta / Edición
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _idProfesorEditando == null
                              ? 'Registrar Profesor'
                              : 'Editar Profesor',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _nombreController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre Completo',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Ingresa el nombre'
                              : null,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _dniController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'DNI',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Ingresa el DNI'
                              : null,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _telefonoController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Ingresa un teléfono'
                              : null,
                        ),
                        const SizedBox(height: 20),

                        // Selector Múltiple de Especialidades (Chips)
                        const Text(
                          'Especialidades / Clases:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _deportesDisponibles.map((deporte) {
                            final seleccionado = _especialidadesSeleccionadas
                                .contains(deporte);
                            return FilterChip(
                              label: Text(deporte),
                              selected: seleccionado,
                              onSelected: (bool val) {
                                setState(() {
                                  if (val) {
                                    _especialidadesSeleccionadas.add(deporte);
                                  } else {
                                    _especialidadesSeleccionadas.remove(
                                      deporte,
                                    );
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 32),

                        Row(
                          children: [
                            if (_idProfesorEditando != null) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _limpiarFormulario,
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _guardarProfesor,
                                child: Text(
                                  _idProfesorEditando == null
                                      ? 'Dar de Alta'
                                      : 'Guardar Cambios',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),

            // COLUMNA DERECHA: Nómina y Explorador de Alumnos
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  // Nómina del Staff
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nómina del Staff de Profesores',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Toca un profesor para gestionar sus alumnos.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('profesores')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final docs = snapshot.data!.docs;

                                return ListView.separated(
                                  itemCount: docs.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(color: Color(0xFFF1F5F9)),
                                  itemBuilder: (context, index) {
                                    final profe = ProfesorModel.fromFirestore(
                                      docs[index].id,
                                      docs[index].data()
                                          as Map<String, dynamic>,
                                    );
                                    final esSeleccionado =
                                        _profesorSeleccionado?.id == profe.id;

                                    return ListTile(
                                      selected: esSeleccionado,
                                      selectedTileColor: Colors.blue.withValues(
                                        alpha: 0.05,
                                      ),
                                      title: Text(
                                        profe.nombre,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Especialidades: ${profe.especialidades.join(", ")} • Tel: ${profe.telefono}',
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _profesorSeleccionado = profe;
                                        });
                                      },
                                      trailing: IconButton(
                                        icon: const Icon(
                                          Icons.edit_rounded,
                                          color: Colors.blueGrey,
                                        ),
                                        onPressed: () =>
                                            _prepararEdicion(profe),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Panel Inferior: Alumnos del Profesor Seleccionado
                  if (_profesorSeleccionado != null) ...[
                    const SizedBox(height: 24),
                    Expanded(
                      flex: 1,
                      child: AlumnosPorProfesorView(
                        profesor: _profesorSeleccionado!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
