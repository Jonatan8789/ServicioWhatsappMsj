import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'rutina_model.dart';

class MiRutinaPage extends StatelessWidget {
  const MiRutinaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('No se pudo identificar al socio.'));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rutinas_gimnasio')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.data!.exists) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Todavía no tenés una rutina asignada.\n'
                'Pedile al profesor que te la cargue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final rutina = RutinaModel.fromFirestore(
          user.uid,
          snapshot.data!.data() as Map<String, dynamic>,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Asignada por ${rutina.asignadoPorNombre} el '
              '${rutina.fechaAsignacion.day}/${rutina.fechaAsignacion.month}/${rutina.fechaAsignacion.year}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (rutina.notas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFFEFF6FF),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(rutina.notas),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...rutina.ejercicios.map(
              (e) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(
                    Icons.fitness_center,
                    color: Color(0xFF0A3B43),
                  ),
                  title: Text(
                    e.nombre,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${e.series} series x ${e.repeticiones} repeticiones · '
                    'Descanso ${e.descansoSegundos}s',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
