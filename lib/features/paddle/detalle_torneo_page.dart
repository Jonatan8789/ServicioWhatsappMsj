import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Importamos el modal desde su propio archivo
import 'inscripcion_torneo_dialog.dart';

class DetalleTorneoPage extends StatefulWidget {
  final String torneoId;
  final bool esAdmin;

  const DetalleTorneoPage({
    super.key,
    required this.torneoId,
    this.esAdmin = false,
  });

  @override
  State<DetalleTorneoPage> createState() => _DetalleTorneoPageState();
}

class _DetalleTorneoPageState extends State<DetalleTorneoPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _abrirModalInscripcion(Map<String, dynamic> torneoData) async {
    final bool? inscripto = await showDialog<bool>(
      context: context,
      builder: (context) => InscripcionTorneoDialog(
        torneoId: widget.torneoId,
        nombreTorneo: torneoData['nombre'] ?? 'Torneo de Pádel',
        precioInscripcion:
            (torneoData['precioInscripcion'] as num?)?.toDouble() ?? 0.0,
      ),
    );

    if (inscripto == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pareja inscripta e ingreso asentado correctamente.'),
          backgroundColor: Color(0xFF0A3B43),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('torneos').doc(widget.torneoId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final torneoData = snapshot.data!.data() as Map<String, dynamic>? ?? {};

        return Scaffold(
          appBar: AppBar(
            title: Text(torneoData['nombre'] ?? 'Detalle del Torneo'),
            backgroundColor: const Color(0xFF0A3B43),
            foregroundColor: Colors.white,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _abrirModalInscripcion(torneoData),
            backgroundColor: const Color(0xFF0A3B43),
            icon: const Icon(Icons.group_add, color: Colors.white),
            label: const Text(
              'Inscribir Pareja',
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  torneoData['nombre'] ?? 'Sin Nombre',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Categoría: ${torneoData['categoria'] ?? 'General'} | Precio: \$${torneoData['precioInscripcion'] ?? 0}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Parejas Inscriptas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('torneos')
                        .doc(widget.torneoId)
                        .collection('parejas_inscriptas')
                        .orderBy('fechaInscripcion', descending: true)
                        .snapshots(),
                    builder: (context, subSnapshot) {
                      if (!subSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final parejas = subSnapshot.data!.docs;

                      if (parejas.isEmpty) {
                        return const Center(
                          child: Text('No hay parejas inscriptas aún.'),
                        );
                      }

                      return ListView.builder(
                        itemCount: parejas.length,
                        itemBuilder: (context, i) {
                          final p = parejas[i].data() as Map<String, dynamic>;
                          final j1 = p['jugador1'] ?? {};
                          final j2 = p['jugador2'] ?? {};

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(
                                Icons.sports_tennis,
                                color: Color(0xFF0A3B43),
                              ),
                              title: Text(
                                '${j1['nombreCompleto']} y ${j2['nombreCompleto']}',
                              ),
                              subtitle: Text(
                                'Tel: ${j1['telefono']} / ${j2['telefono']} | Estado: ${p['estadoPago']}',
                              ),
                              trailing: Chip(
                                label: Text(
                                  p['estadoPago'] == 'pagado'
                                      ? 'PAGADO'
                                      : 'PENDIENTE',
                                  style: TextStyle(
                                    color: p['estadoPago'] == 'pagado'
                                        ? Colors.green.shade900
                                        : Colors.orange.shade900,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                backgroundColor: p['estadoPago'] == 'pagado'
                                    ? Colors.green.shade50
                                    : Colors.orange.shade50,
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
        );
      },
    );
  }
}
