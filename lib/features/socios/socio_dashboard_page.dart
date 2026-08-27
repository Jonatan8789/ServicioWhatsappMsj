import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'socio_reserva_paddle_page.dart';

class SocioDashboardPage extends StatelessWidget {
  final String socioId;
  final Map<String, dynamic> socioData;

  const SocioDashboardPage({
    super.key,
    required this.socioId,
    required this.socioData,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0A3B43);
    final String mesActual =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}";

    // 🎯 Detección de límite por frecuencia registrada
    final String frecuenciaRaw = (socioData['frecuencia'] ?? 'Pase Libre')
        .toString()
        .toLowerCase();
    int limiteCalculado = 999;
    if (frecuenciaRaw.contains('1') || frecuenciaRaw.contains('una')) {
      limiteCalculado = 4;
    } else if (frecuenciaRaw.contains('2') || frecuenciaRaw.contains('dos')) {
      limiteCalculado = 8;
    } else if (frecuenciaRaw.contains('3') || frecuenciaRaw.contains('tres')) {
      limiteCalculado = 12;
    } else if (frecuenciaRaw.contains('4') ||
        frecuenciaRaw.contains('cuatro')) {
      limiteCalculado = 16;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Hola, ${socioData['nombre'] ?? 'Socio'}'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CARD DE SOCIO
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: primaryColor.withOpacity(0.1),
                      backgroundImage: (socioData['fotoUrl'] ?? '').isNotEmpty
                          ? NetworkImage(socioData['fotoUrl'])
                          : null,
                      child: (socioData['fotoUrl'] ?? '').isEmpty
                          ? const Icon(Icons.person, color: primaryColor)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${socioData['nombre']} ${socioData['apellido'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'DNI: ${socioData['dni']}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: socioData['matriculaAlDia'] == true
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              socioData['matriculaAlDia'] == true
                                  ? 'Matrícula Al Día'
                                  : 'Matrícula Pendiente',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: socioData['matriculaAlDia'] == true
                                    ? Colors.green.shade800
                                    : Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // STREAM DE CONSUMO MENSUAL
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('socios')
                  .doc(socioId)
                  .collection('creditos_mensuales')
                  .doc(mesActual)
                  .snapshots(),
              builder: (context, snapshot) {
                int clasesUsadas = 0;
                int limite = limiteCalculado;

                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  clasesUsadas = (data['clasesUsadas'] as num?)?.toInt() ?? 0;
                  final limBase =
                      (data['limiteClases'] as num?)?.toInt() ?? 999;
                  if (limBase != 999) limite = limBase;
                }

                String detalleClases = limite == 999
                    ? 'Pase Libre Activo'
                    : 'Consumidas: $clasesUsadas de $limite clases';

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mi Pase Mensual',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        socioData['frecuencia'] ?? 'Pase Libre',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detalleClases,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // RESERVAR PÁDEL
            const Text(
              'Servicios',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(
                Icons.sports_tennis_rounded,
                color: primaryColor,
              ),
              title: const Text(
                'Reservar Cancha de Pádel',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Alquiler de turnos y paletas'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SocioReservaPaddlePage(
                      socioId: socioId,
                      socioNombre: socioData['nombre'] ?? 'Socio',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
