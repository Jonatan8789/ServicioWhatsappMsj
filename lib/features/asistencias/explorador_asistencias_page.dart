import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../shared/data_explorer.dart';
import '../../theme/app_theme.dart';

class _RegistroAcceso {
  final String nombre;
  final String dni;
  final String tipoEntidad;
  final String modo;
  final DateTime fechaHora;

  _RegistroAcceso({
    required this.nombre,
    required this.dni,
    required this.tipoEntidad,
    required this.modo,
    required this.fechaHora,
  });

  factory _RegistroAcceso.fromFirestore(Map<String, dynamic> data) {
    return _RegistroAcceso(
      nombre: data['nombreSocio']?.toString() ?? 'Usuario',
      dni: data['dniSocio']?.toString() ?? 'S/D',
      tipoEntidad: data['tipoEntidad']?.toString() ?? 'Socio',
      modo: data['modo']?.toString() ?? '-',
      fechaHora: (data['fechaHora'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Explorador histórico de asistencias/accesos — antes el único lugar para
/// ver ingresos era el "Monitor Acceso en Vivo" de Control de Acceso, que
/// sólo muestra el día de hoy y no tiene búsqueda ni exportación. Éste lee
/// toda la colección 'asistencias_accesos' (socios + profesores) con rango
/// de fechas real.
class ExploradorAsistenciasPage extends StatelessWidget {
  const ExploradorAsistenciasPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DateTime hace30Dias = DateTime.now().subtract(const Duration(days: 30));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Explorador de Asistencias')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<QuerySnapshot>(
          // 🚨 Sin límite de fecha esto crecería sin techo con los años; se
          // trae por defecto sólo lo de los últimos 30 días (el usuario
          // puede ampliar el rango con el selector de fechas del explorador,
          // que vuelve a filtrar sobre esta misma ventana cargada).
          stream: FirebaseFirestore.instance
              .collection('asistencias_accesos')
              .where(
                'fechaHora',
                isGreaterThanOrEqualTo: Timestamp.fromDate(hace30Dias),
              )
              .orderBy('fechaHora', descending: true)
              .limit(3000)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final registros = snapshot.data!.docs
                .map(
                  (d) => _RegistroAcceso.fromFirestore(
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Mostrando los últimos 30 días. Usá el filtro de fechas '
                    'para acotar el rango.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: registros.isEmpty
                      ? const Center(
                          child: Text('No hay accesos registrados en este período.'),
                        )
                      : DataExplorer<_RegistroAcceso>(
                          items: registros,
                          nombreArchivoCsv: 'asistencias',
                          fechaDe: (r) => r.fechaHora,
                          columnas: [
                            ColumnaExplorador(
                              etiqueta: 'Fecha y Hora',
                              texto: (r) =>
                                  DateFormat('dd/MM/yyyy HH:mm').format(r.fechaHora),
                              orden: (r) => r.fechaHora,
                            ),
                            ColumnaExplorador(
                              etiqueta: 'Nombre',
                              texto: (r) => r.nombre,
                            ),
                            ColumnaExplorador(etiqueta: 'DNI', texto: (r) => r.dni),
                            ColumnaExplorador(
                              etiqueta: 'Tipo',
                              texto: (r) => r.tipoEntidad,
                            ),
                            ColumnaExplorador(etiqueta: 'Modo', texto: (r) => r.modo),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
