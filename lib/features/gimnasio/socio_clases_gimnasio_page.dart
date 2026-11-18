import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'clase_gimnasio_model.dart';
import 'clase_gimnasio_repository.dart';

class SocioClasesGimnasioPage extends StatefulWidget {
  const SocioClasesGimnasioPage({super.key});

  @override
  State<SocioClasesGimnasioPage> createState() =>
      _SocioClasesGimnasioPageState();
}

class _SocioClasesGimnasioPageState extends State<SocioClasesGimnasioPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime _fechaSeleccionada = DateTime.now();
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

  Future<void> _inscribirse(ClaseGimnasioModel clase) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
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
      final entroDirecto = await inscribirseAClaseAtomica(
        firestore: _firestore,
        claseId: clase.id,
        socioId: _socioDocId!,
        socioNombre: nombreSocio,
      );
      _snack(
        entroDirecto
            ? '✅ ¡Anotado en ${clase.nombre}!'
            : '⏳ La clase está completa, quedaste en lista de espera.',
        entroDirecto ? Colors.green : Colors.orange,
      );
    } on YaInscriptoException {
      _snack('Ya estás anotado en esa clase.', Colors.orange);
    } catch (e) {
      _snack('Error: $e', Colors.red);
    }
  }

  Future<void> _cancelar(ClaseGimnasioModel clase) async {
    if (_socioDocId == null) return;
    await cancelarInscripcionClaseAtomica(
      firestore: _firestore,
      claseId: clase.id,
      socioId: _socioDocId!,
    );
    _snack('Te diste de baja de ${clase.nombre}.', Colors.orange);
  }

  @override
  Widget build(BuildContext context) {
    final socioDocId = _socioDocId;
    final inicioDia = DateTime(
      _fechaSeleccionada.year,
      _fechaSeleccionada.month,
      _fechaSeleccionada.day,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Clases del Gimnasio'),
        backgroundColor: const Color(0xFF0A3B43),
        foregroundColor: Colors.white,
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
                  label: const Text('Cambiar'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fechaSeleccionada,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 14)),
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
                      'No hay clases programadas este día.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: clases.length,
                  itemBuilder: (context, i) {
                    final c = clases[i];
                    final inscripto =
                        socioDocId != null &&
                        c.inscriptosIds.contains(socioDocId);
                    final enEspera =
                        socioDocId != null &&
                        c.listaEsperaIds.contains(socioDocId);
                    final lugares = c.cupoMaximo - c.inscriptosIds.length;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c.nombre} · ${c.horaInicio.toString().padLeft(2, '0')}:00 hs',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Profesor: ${c.profesorNombre}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            Text(
                              lugares > 0
                                  ? 'Lugares disponibles: $lugares/${c.cupoMaximo}'
                                  : 'Completo (${c.listaEsperaIds.length} en lista de espera)',
                            ),
                            const SizedBox(height: 8),
                            if (inscripto || enEspera)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => _cancelar(c),
                                  child: Text(
                                    enEspera
                                        ? 'Salir de la lista de espera'
                                        : 'Cancelar mi lugar',
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0A3B43),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => _inscribirse(c),
                                  child: Text(
                                    lugares > 0
                                        ? 'Inscribirme'
                                        : 'Anotarme en lista de espera',
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
