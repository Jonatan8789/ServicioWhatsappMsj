import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MonitorCocinaPage extends StatefulWidget {
  const MonitorCocinaPage({super.key});

  @override
  State<MonitorCocinaPage> createState() => _MonitorCocinaPageState();
}

class _MonitorCocinaPageState extends State<MonitorCocinaPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.soup_kitchen_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('Monitor de Cocina (KDS) - Comandas en Vivo'),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('ventas_buffet')
            .where('estadoCocina', isEqualTo: 'Pendiente')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            );
          }

          final docs = snapshot.data!.docs;

          // 🍳 FILTRO KDS: Muestra el pedido solo si contiene productos con requiereCocina == true
          final pedidosCocina = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final List items = data['items'] ?? [];
            return items.any((it) => it['requiereCocina'] == true);
          }).toList();

          if (pedidosCocina.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 70,
                    color: Colors.green,
                  ),
                  SizedBox(height: 16),
                  Text(
                    '¡Sin comandas pendientes en cocina!',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: pedidosCocina.length,
            itemBuilder: (context, i) {
              final doc = pedidosCocina[i];
              final data = doc.data() as Map<String, dynamic>;
              final String origen = data['origen_salón'] ?? 'Mostrador';
              final DateTime fecha = (data['fecha'] as Timestamp).toDate();
              final List items = data['items'] ?? [];

              // Filtra solo los ítems del pedido que requieren preparación
              final itemsCocina = items
                  .where((it) => it['requiereCocina'] == true)
                  .toList();

              return Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.orange, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            origen,
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            DateFormat('HH:mm').format(fecha),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 20),
                      Expanded(
                        child: ListView.builder(
                          itemCount: itemsCocina.length,
                          itemBuilder: (context, idx) {
                            final it = itemsCocina[idx];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Text(
                                '• ${it['cantidad']}x ${it['nombre']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(45),
                        ),
                        onPressed: () async {
                          await _firestore
                              .collection('ventas_buffet')
                              .doc(doc.id)
                              .update({'estadoCocina': 'Entregado'});
                        },
                        icon: const Icon(Icons.done_all_rounded),
                        label: const Text(
                          'MARCAR ENTREGADO',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
    );
  }
}
