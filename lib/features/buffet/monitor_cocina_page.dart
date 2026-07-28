import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MonitorCocinaPage extends StatelessWidget {
  const MonitorCocinaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: const Color(
        0xFF0F172A,
      ), // Fondo oscuro industrial de cocina
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.soup_kitchen, color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Monitor de Cocina & Barra • Despacho en Vivo',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: StreamBuilder<QuerySnapshot>(
          // Escucha activa de comandas no entregadas ordenadas cronológicamente
          stream: firestore
              .collection('comandas_cocina')
              .where('estado', whereIn: ['Pendiente', 'En Preparación'])
              .orderBy('fecha', descending: false)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              );
            }
            final comandas = snapshot.data?.docs ?? [];

            if (comandas.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 80,
                      color: Colors.tealAccent,
                    ),
                    SizedBox(height: 16),
                    Text(
                      '¡Cocina limpia! No hay minutas pendientes.',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }

            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 380,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: comandas.length,
              itemBuilder: (context, idx) {
                final doc = comandas[idx];
                final data = doc.data() as Map<String, dynamic>;
                final List<dynamic> detalles = data['detalles'] ?? [];
                final String estado = data['estado'] ?? 'Pendiente';
                final String ubicacion = data['mesa'] ?? 'Mostrador';

                final bool enPreparacion = estado == 'En Preparación';

                return Card(
                  color: enPreparacion
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF334155),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: enPreparacion
                          ? Colors.amber.shade600
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // CABECERA DE LA COMANDA
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: enPreparacion
                                    ? Colors.amber
                                    : Colors.red.shade600,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                ubicacion.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            Text(
                              estado.toUpperCase(),
                              style: TextStyle(
                                color: enPreparacion
                                    ? const Color.fromARGB(255, 189, 211, 108)
                                    : Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Colors.white12, height: 1),
                        const SizedBox(height: 12),

                        // LISTADO DE PLATOS A COCINAR
                        Expanded(
                          child: ListView.builder(
                            itemCount: detalles.length,
                            itemBuilder: (context, iIdx) {
                              final item = detalles[iIdx];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4.0,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '${item['cantidad']} x  ',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        item['nombre'] ?? '',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // BOTÓN INTERACTIVO DE CONTROL DE ESTADOS DE COCINA
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: enPreparacion
                                  ? Colors.teal.shade600
                                  : Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () async {
                              if (!enPreparacion) {
                                // Pasa de Pendiente -> En Preparación
                                await firestore
                                    .collection('comandas_cocina')
                                    .doc(doc.id)
                                    .update({'estado': 'En Preparación'});
                              } else {
                                // Pasa de En Preparación -> Listo (Desaparece del monitor de cocina)
                                await firestore
                                    .collection('comandas_cocina')
                                    .doc(doc.id)
                                    .update({'estado': 'Listo'});
                              }
                            },
                            child: Text(
                              enPreparacion
                                  ? '✔ ENVIAR A MOSTRADOR (LISTO)'
                                  : '🔥 EMPEZAR A COCINAR',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
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
    );
  }
}
