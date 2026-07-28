import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profesor_model.dart';
import 'cronograma_model.dart';

class CronogramasPage extends StatefulWidget {
  const CronogramasPage({super.key});

  @override
  State<CronogramasPage> createState() => _CronogramasPageState();
}

class _CronogramasPageState extends State<CronogramasPage> {
  final _formKey = GlobalKey<FormState>();

  List<String> _bloquesHorarios = [];
  List<String> _actividadesPermitidas = [];

  final List<String> _diasSemana = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];
  final List<String> _diasSeleccionados = [];

  String? _profesorSelId;
  String? _profesorSelNombre;
  String? _deporteSel;
  String? _bloqueSel;
  bool _cargandoHorarios = true;
  String? _errorMensaje;

  @override
  void initState() {
    super.initState();
    _cargarHorariosBase();
  }

  Future<void> _cargarHorariosBase() async {
    try {
      final db = FirebaseFirestore.instance;

      final horariosDoc = await db
          .collection('configuracion')
          .doc('horarios')
          .get();

      List<String> bloquesCargados = [];

      if (horariosDoc.exists && horariosDoc.data() != null) {
        final data = horariosDoc.data()!;

        // Obtenemos el array guardado en el documento
        final raw =
            data['bloques'] ??
            data['lista'] ??
            data['horarios'] ??
            data['items'];

        if (raw is List) {
          for (var item in raw) {
            if (item is Map) {
              final inicio = item['horaInicio']?.toString().trim() ?? '';
              final fin = item['horaFin']?.toString().trim() ?? '';
              final nombre = item['nombre']?.toString().trim() ?? '';
              final id = item['id']?.toString().trim() ?? '';

              // 1. Si tenemos horaInicio y horaFin, armamos el rango visual completo
              if (inicio.isNotEmpty && fin.isNotEmpty) {
                if (nombre.isNotEmpty) {
                  bloquesCargados.add('$inicio a $fin hs ($nombre)');
                } else {
                  bloquesCargados.add('$inicio a $fin hs');
                }
              }
              // 2. Si falta alguna hora, usamos el identificador o nombre como fallback
              else if (nombre.isNotEmpty) {
                bloquesCargados.add(nombre);
              } else if (id.isNotEmpty) {
                bloquesCargados.add(id);
              }
            } else if (item is String) {
              bloquesCargados.add(item);
            }
          }
        }
      }

      setState(() {
        _bloquesHorarios = bloquesCargados;
        _cargandoHorarios = false;
        _errorMensaje = null;
      });
    } catch (e) {
      debugPrint('Error al cargar horarios: $e');
      setState(() {
        _errorMensaje = 'Error al cargar horarios: $e';
        _cargandoHorarios = false;
      });
    }
  }

  Future<void> _guardarCronograma() async {
    if (_profesorSelId == null ||
        _deporteSel == null ||
        _bloqueSel == null ||
        _diasSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor, completa todos los campos y selecciona al menos un día.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final nuevoCronograma = CronogramaModel(
      id: '',
      idProfesor: _profesorSelId!,
      nombreProfesor: _profesorSelNombre!,
      deporte: _deporteSel!,
      dias: List<String>.from(_diasSeleccionados),
      idBloqueHorario: _bloqueSel!,
    );

    await FirebaseFirestore.instance
        .collection('cronogramas')
        .add(nuevoCronograma.toFirestore());

    setState(() {
      _diasSeleccionados.clear();
      _bloqueSel = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Clase asignada al cronograma con éxito!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _eliminarCronograma(String id) async {
    await FirebaseFirestore.instance.collection('cronogramas').doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // COLUMNA IZQUIERDA: Formulario
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Asignación de Cronograma',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (_errorMensaje != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMensaje!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Selector de Profesor mediante StreamBuilder en Tiempo Real
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('profesores')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Text(
                                'Error: ${snapshot.error}',
                                style: const TextStyle(color: Colors.red),
                              );
                            }

                            if (!snapshot.hasData) {
                              return const CircularProgressIndicator();
                            }

                            final docs = snapshot.data!.docs;

                            // Mapeamos los profesores
                            final listaProfes = docs
                                .map((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;

                                  List<String> especialidadesAux = [];
                                  if (data['especialidades'] != null &&
                                      data['especialidades'] is List) {
                                    especialidadesAux = List<String>.from(
                                      data['especialidades'],
                                    );
                                  } else if (data['especialidad'] != null) {
                                    especialidadesAux = [
                                      data['especialidad'].toString(),
                                    ];
                                  }

                                  return ProfesorModel(
                                    id: doc.id,
                                    nombre: data['nombre'] ?? 'Sin Nombre',
                                    dni: data['dni'] ?? '',
                                    telefono: data['telefono'] ?? '',
                                    especialidades: especialidadesAux,
                                    activo: data['activo'] ?? true,
                                  );
                                })
                                .where((p) => p.activo)
                                .toList();

                            if (listaProfes.isEmpty) {
                              return const Text(
                                'No hay profesores registrados o activos.',
                                style: TextStyle(color: Colors.orange),
                              );
                            }

                            return DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Seleccionar Profesor',
                                border: OutlineInputBorder(),
                              ),
                              value: _profesorSelId,
                              items: listaProfes
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p.id,
                                      child: Text(p.nombre),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  _profesorSelId = val;
                                  final profeElegido = listaProfes.firstWhere(
                                    (p) => p.id == val,
                                  );
                                  _profesorSelNombre = profeElegido.nombre;
                                  _actividadesPermitidas = List<String>.from(
                                    profeElegido.especialidades,
                                  );

                                  if (_actividadesPermitidas.length == 1) {
                                    _deporteSel = _actividadesPermitidas.first;
                                  } else {
                                    _deporteSel = null;
                                  }
                                });
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // Selector de Deporte / Actividad
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Actividad / Clase',
                            border: OutlineInputBorder(),
                            hintText: 'Selecciona primero un profesor',
                          ),
                          value: _deporteSel,
                          items: _actividadesPermitidas
                              .map(
                                (d) =>
                                    DropdownMenuItem(value: d, child: Text(d)),
                              )
                              .toList(),
                          onChanged: (val) => setState(() => _deporteSel = val),
                        ),
                        const SizedBox(height: 20),

                        // Selector de Bloque Horario
                        _cargandoHorarios
                            ? const CircularProgressIndicator()
                            : DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Bloque Horario Estructurado',
                                  border: OutlineInputBorder(),
                                ),
                                value: _bloqueSel,
                                items: _bloquesHorarios
                                    .map(
                                      (b) => DropdownMenuItem(
                                        value: b,
                                        child: Text(b),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => _bloqueSel = val),
                              ),
                        const SizedBox(height: 24),

                        // Selector Multi-Días
                        const Text(
                          'Días de dictado:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _diasSemana.map((dia) {
                            final bool seleccionado = _diasSeleccionados
                                .contains(dia);
                            return FilterChip(
                              label: Text(dia),
                              selected: seleccionado,
                              selectedColor: Colors.teal.withValues(
                                alpha: 0.15,
                              ),
                              checkmarkColor: Colors.teal,
                              labelStyle: TextStyle(
                                color: seleccionado
                                    ? Colors.teal.shade800
                                    : Colors.black87,
                                fontWeight: seleccionado
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              onSelected: (bool valor) {
                                setState(() {
                                  if (valor) {
                                    _diasSeleccionados.add(dia);
                                  } else {
                                    _diasSeleccionados.remove(dia);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 32),

                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Vincular Horario',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _guardarCronograma,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),

            // COLUMNA DERECHA: Grilla de cronograma general
            Expanded(
              flex: 2,
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
                      'Cronograma General de Clases',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('cronogramas')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final docs = snapshot.data!.docs;

                          if (docs.isEmpty) {
                            return const Center(
                              child: Text(
                                'No hay grillas de horarios asignadas todavía.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, _) =>
                                const Divider(color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              final crono = CronogramaModel.fromFirestore(
                                docs[index].id,
                                docs[index].data() as Map<String, dynamic>,
                              );

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.teal.withValues(
                                    alpha: 0.08,
                                  ),
                                  child: const Icon(
                                    Icons.more_time_rounded,
                                    color: Colors.teal,
                                  ),
                                ),
                                title: Text(
                                  "${crono.deporte} — ${crono.idBloqueHorario} hs",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    "Profesor: ${crono.nombreProfesor}\nDías: ${crono.dias.join(', ')}",
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_sweep_rounded,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () =>
                                      _eliminarCronograma(crono.id),
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
          ],
        ),
      ),
    );
  }
}
