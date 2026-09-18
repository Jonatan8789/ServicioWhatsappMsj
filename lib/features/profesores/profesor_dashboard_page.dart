import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/fichaje_profesor_service.dart';
import '../auth/login_page.dart';

/// Portal móvil de autoservicio para profesores — antes no existía ningún
/// login funcional para este rol (ver login_page.dart / main.dart): un
/// profesor no tenía forma de fichar su propia entrada/salida, ver su
/// horario asignado ni sus horas del mes sin pasarle el teléfono/DNI a
/// recepción. Reutiliza FichajeProfesorService (la misma lógica que usa
/// control_acceso_page.dart en recepción) para que el fichaje autoservicio
/// y el de mostrador alimenten exactamente el mismo pipeline de liquidación.
class ProfesorDashboardPage extends StatefulWidget {
  final String profesorId;
  final Map<String, dynamic> profesorData;

  const ProfesorDashboardPage({
    super.key,
    required this.profesorId,
    required this.profesorData,
  });

  @override
  State<ProfesorDashboardPage> createState() => _ProfesorDashboardPageState();
}

class _ProfesorDashboardPageState extends State<ProfesorDashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Color primaryColor = Color(0xFF0A3B43);

  bool _fichando = false;
  final Map<String, String> _cacheHorarios = {};

  // 🚨 DateFormat('MMMM', 'es') requiere initializeDateFormatting(), que esta
  // app nunca llama — usar ese locale explícito tira LocaleDataException en
  // tiempo de ejecución. Se arma el nombre del mes a mano, como ya hace
  // liquidacion_cuotas_page.dart con su mapa de meses.
  static const List<String> _nombresMeses = [
    '',
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  String get _hoyStr {
    final hoy = DateTime.now();
    return "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}";
  }

  Future<void> _marcarFichaje(String proximoTipo) async {
    setState(() => _fichando = true);
    try {
      final String tipo = await FichajeProfesorService.ficharProfesor(
        profesorId: widget.profesorId,
        nombreProfesor: widget.profesorData['nombre'] ?? 'Profesor',
        dniProfesor: widget.profesorData['dni'] ?? '',
        especialidad:
            (widget.profesorData['especialidades'] as List?)?.isNotEmpty ==
                true
            ? (widget.profesorData['especialidades'] as List).first
                  .toString()
            : '',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $tipo registrada correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al fichar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _fichando = false);
    }
  }

  Future<String> _traducirBloqueHorario(String bloqueId) async {
    if (bloqueId.isEmpty) return 'Sin horario asignado';
    if (_cacheHorarios.containsKey(bloqueId)) return _cacheHorarios[bloqueId]!;

    try {
      final docHorarios = await _firestore
          .collection('configuracion')
          .doc('horarios')
          .get();

      if (docHorarios.exists && docHorarios.data() != null) {
        final bloques = docHorarios.data()!['bloques'] as List<dynamic>? ?? [];
        for (var b in bloques) {
          if (b['id'] == bloqueId) {
            final desde = b['horaInicio'] ?? '';
            final hasta = b['horaFin'] ?? '';
            final nombre = b['nombre'] ?? '';
            final String texto = desde.isNotEmpty && hasta.isNotEmpty
                ? '$nombre ($desde a $hasta hs)'
                : (nombre.isNotEmpty ? nombre : bloqueId);
            _cacheHorarios[bloqueId] = texto;
            return texto;
          }
        }
      }
    } catch (_) {}
    return bloqueId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Hola, ${widget.profesorData['nombre'] ?? 'Profe'}'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTarjetaFichaje(),
            const SizedBox(height: 24),
            const Text(
              'Mi Horario',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildMiHorario(),
            const SizedBox(height: 24),
            const Text(
              'Mis Horas del Mes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildMisHoras(),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaFichaje() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('asistencia')
          .where('profesorId', isEqualTo: widget.profesorId)
          .where('fechaStr', isEqualTo: _hoyStr)
          .snapshots(),
      builder: (context, snapshot) {
        String tipoUltimo = 'Salida'; // sin fichadas hoy -> próxima es Entrada
        String? horaUltima;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs = snapshot.data!.docs;
          docs.sort((a, b) {
            final fa = (a.data() as Map)['fecha'] as Timestamp?;
            final fb = (b.data() as Map)['fecha'] as Timestamp?;
            return (fb?.toDate() ?? DateTime(0)).compareTo(
              fa?.toDate() ?? DateTime(0),
            );
          });
          final ultimo = docs.first.data() as Map<String, dynamic>;
          tipoUltimo = ultimo['tipo'] ?? 'Salida';
          horaUltima = ultimo['hora'];
        }

        final bool proximaEsEntrada = tipoUltimo != 'Entrada';
        final String proximoTipo = proximaEsEntrada ? 'Entrada' : 'Salida';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                horaUltima != null
                    ? 'Último fichaje: $tipoUltimo a las $horaUltima hs'
                    : 'Todavía no fichaste hoy.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: proximaEsEntrada
                        ? Colors.tealAccent
                        : Colors.orangeAccent,
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _fichando
                      ? null
                      : () => _marcarFichaje(proximoTipo),
                  icon: _fichando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          proximaEsEntrada
                              ? Icons.login_rounded
                              : Icons.logout_rounded,
                        ),
                  label: Text(
                    'Marcar $proximoTipo',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiHorario() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('cronogramas')
          .where('idProfesor', isEqualTo: widget.profesorId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Text(
            'No tenés horarios asignados todavía.',
            style: TextStyle(color: Colors.grey),
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String deporte = data['deporte'] ?? 'Actividad';
            final List<String> dias = List<String>.from(data['dias'] ?? []);
            final String bloqueId = data['idBloqueHorario'] ?? '';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(Icons.schedule_rounded, color: primaryColor),
                title: Text(
                  deporte,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dias.isNotEmpty ? dias.join(', ') : 'Sin días'),
                    FutureBuilder<String>(
                      future: _traducirBloqueHorario(bloqueId),
                      builder: (context, snap) =>
                          Text(snap.data ?? 'Cargando horario...'),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMisHoras() {
    final DateTime hoy = DateTime.now();
    final DateTime inicioMes = DateTime(hoy.year, hoy.month, 1);
    final DateTime finMes = DateTime(hoy.year, hoy.month + 1, 0, 23, 59, 59);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('registro_horas_profes')
          .where('profesorId', isEqualTo: widget.profesorId)
          .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioMes))
          .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(finMes))
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        double totalHoras = 0.0;
        for (var doc in docs) {
          totalHoras +=
              ((doc.data() as Map)['cantidadHoras'] as num?)?.toDouble() ??
              0.0;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_nombresMeses[hoy.month]} ${hoy.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${totalHoras.toStringAsFixed(1)} hs',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              const Text(
                'Sin sesiones registradas este mes todavía.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final DateTime fecha = (data['fecha'] as Timestamp).toDate();
                final double horas =
                    (data['cantidadHoras'] as num?)?.toDouble() ?? 0.0;
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  title: Text(DateFormat('dd/MM/yyyy').format(fecha)),
                  subtitle: Text(data['actividad'] ?? 'Natatorio'),
                  trailing: Text(
                    '${horas.toStringAsFixed(1)} hs',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
