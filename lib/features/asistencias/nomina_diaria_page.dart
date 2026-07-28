import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natatorio_app/features/profesores/profesor_model.dart';
import 'package:natatorio_app/features/asistencias/asistencia_model.dart';
import 'package:natatorio_app/features/profesores/profesor_model.dart';

class NominaDiariaPage extends StatefulWidget {
  const NominaDiariaPage({super.key});

  @override
  State<NominaDiariaPage> createState() => _NominaDiariaPageState();
}

class _NominaDiariaPageState extends State<NominaDiariaPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _filtroNombre = "";

  Future<void> _registrarAsistencia(ProfesorModel profesor, String tipo) async {
    final hoy = DateTime.now();
    final idRegistro =
        "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}_${profesor.id}_$tipo";

    final asistencia = AsistenciaModel(
      id: idRegistro,
      profesorId: profesor.id,
      nombreProfesor: profesor.nombre,
      specialty: profesor.especialidades.join(
        ', ',
      ), // Uniendo especialidades en una cadena
      fecha: hoy,
      tipo: tipo,
      hora:
          "${hoy.hour.toString().padLeft(2, '0')}:${hoy.minute.toString().padLeft(2, '0')}",
    );

    try {
      await _firestore
          .collection('asistencia')
          .doc(idRegistro)
          .set(asistencia.toFirestore());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡$tipo registrada para ${profesor.nombre}!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            // PANEL IZQUIERDO: Profesores
            Expanded(
              flex: 5,
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
                      'Control de Asistencia Diaria',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar profesor por nombre...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) =>
                          setState(() => _filtroNombre = val.toLowerCase()),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('profesores')
                            .where('activo', isEqualTo: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final List<QueryDocumentSnapshot> docs =
                              snapshot.data!.docs;
                          final filteredDocs = docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>?;
                            final nombre = data != null
                                ? (data['nombre']?.toString().toLowerCase() ??
                                      "")
                                : "";
                            return nombre.contains(_filtroNombre);
                          }).toList();

                          return ListView.separated(
                            itemCount: filteredDocs.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, index) {
                              final doc = filteredDocs[index];
                              final profe = ProfesorModel.fromFirestore(
                                doc.id,
                                doc.data() as Map<String, dynamic>,
                              );
                              return ListTile(
                                title: Text(
                                  profe.nombre,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(profe.especialidades.join(', ')),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _registrarAsistencia(
                                        profe,
                                        'Entrada',
                                      ),
                                      child: const Text('Entrada'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber.shade700,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () =>
                                          _registrarAsistencia(profe, 'Salida'),
                                      child: const Text('Salida'),
                                    ),
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
              ),
            ),
            const SizedBox(width: 40),
            // PANEL DERECHO: Historial
            Expanded(
              flex: 4,
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
                      'Fichadas de Hoy',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('asistencia')
                            .orderBy('fecha', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final registros = snapshot.data!.docs;
                          return ListView.builder(
                            itemCount: registros.length,
                            itemBuilder: (context, index) {
                              final doc = registros[index];
                              final asistencia = AsistenciaModel.fromFirestore(
                                doc.id,
                                doc.data() as Map<String, dynamic>,
                              );
                              final esEntrada = asistencia.tipo == 'Entrada';
                              return ListTile(
                                leading: Icon(
                                  esEntrada
                                      ? Icons.check_circle
                                      : Icons.remove_circle,
                                  color: esEntrada ? Colors.teal : Colors.amber,
                                ),
                                title: Text(asistencia.nombreProfesor),
                                subtitle: Text(asistencia.tipo),
                                trailing: Text(
                                  asistencia.hora,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
