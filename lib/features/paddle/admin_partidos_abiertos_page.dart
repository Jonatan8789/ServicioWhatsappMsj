import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'partido_abierto_model.dart';
import 'reserva_cancha_model.dart';
import 'reserva_cancha_repository.dart';

class AdminPartidosAbiertosPage extends StatefulWidget {
  const AdminPartidosAbiertosPage({super.key});

  @override
  State<AdminPartidosAbiertosPage> createState() =>
      _AdminPartidosAbiertosPageState();
}

class _AdminPartidosAbiertosPageState
    extends State<AdminPartidosAbiertosPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _cancelarPartido(PartidoAbiertoModel partido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar este Partido Abierto?'),
        content: Text(
          'Se liberará la cancha ${partido.cancha} '
          '(${partido.horaInicio}:00 hs) y se desanotarán '
          '${partido.jugadoresIds.length} jugador(es). Las ventas '
          'pendientes ya generadas quedan a tu criterio anularlas en caja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancelar partido',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _firestore
          .collection('partidos_abiertos')
          .doc(partido.id)
          .update({'estado': 'Cancelado'});

      await cancelarReservaCanchaAtomica(
        firestore: _firestore,
        reserva: ReservaCanchaModel(
          id: partido.reservaId,
          cancha: partido.cancha,
          nombreCliente: '',
          fecha: partido.fecha,
          horaInicio: partido.horaInicio,
          duracionHoras: partido.duracionHoras,
          precio: partido.precioTotal,
          metodoPago: '',
        ),
      );

      _snack('🔓 Partido cancelado y cancha liberada.', Colors.green);
    } catch (e) {
      _snack('Error al cancelar: $e', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Partidos Abiertos'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('partidos_abiertos')
            .orderBy('creadoEn', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final partidos = snapshot.data!.docs
              .map(
                (d) => PartidoAbiertoModel.fromFirestore(
                  d.id,
                  d.data() as Map<String, dynamic>,
                ),
              )
              .toList();

          if (partidos.isEmpty) {
            return const Center(
              child: Text(
                'Todavía no se creó ningún Partido Abierto.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: partidos.length,
            itemBuilder: (context, i) {
              final p = partidos[i];
              final colorEstado = p.estado == 'Completo'
                  ? Colors.green
                  : (p.estado == 'Cancelado' ? Colors.grey : Colors.blue);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(
                    '${p.cancha} · ${p.fecha.day}/${p.fecha.month}/${p.fecha.year} '
                    '${p.horaInicio.toString().padLeft(2, '0')}:00 hs',
                  ),
                  subtitle: Text(
                    '${p.categoria} · ${p.jugadoresNombres.join(', ')} '
                    '(${p.jugadoresIds.length}/${PartidoAbiertoModel.cupoJugadores})',
                  ),
                  leading: Chip(
                    label: Text(
                      p.estado,
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: colorEstado,
                  ),
                  trailing: p.estado == 'Cancelado'
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.cancel_outlined,
                            color: Colors.red,
                          ),
                          onPressed: () => _cancelarPartido(p),
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
