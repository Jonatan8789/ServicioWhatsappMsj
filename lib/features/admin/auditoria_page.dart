import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../shared/data_explorer.dart';
import '../../theme/app_theme.dart';

class _RegistroAuditoria {
  final String accion;
  final String entidad;
  final String? entidadId;
  final String? email;
  final DateTime fecha;
  final Map<String, dynamic> detalle;

  _RegistroAuditoria({
    required this.accion,
    required this.entidad,
    required this.entidadId,
    required this.email,
    required this.fecha,
    required this.detalle,
  });

  factory _RegistroAuditoria.fromFirestore(Map<String, dynamic> data) {
    return _RegistroAuditoria(
      accion: data['accion']?.toString() ?? '-',
      entidad: data['entidad']?.toString() ?? '-',
      entidadId: data['entidadId']?.toString(),
      email: data['email']?.toString(),
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      detalle: Map<String, dynamic>.from(data['detalle'] ?? {}),
    );
  }
}

/// Registro de auditoría del sistema: quién hizo qué y cuándo, para las
/// operaciones sensibles instrumentadas (cambios de rol/permisos, emisión
/// de facturas y notas de crédito/débito ARCA, anulaciones). No es un log
/// exhaustivo de cada escritura del sistema — cubre las operaciones de
/// mayor impacto/riesgo. La colección es create-only (ver firestore.rules):
/// nadie, ni siquiera un admin, puede editar o borrar un asiento ya escrito.
class AuditoriaPage extends StatelessWidget {
  const AuditoriaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DateTime hace30Dias = DateTime.now().subtract(const Duration(days: 30));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Auditoría del Sistema')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('auditoria_sistema')
              .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(hace30Dias))
              .orderBy('fecha', descending: true)
              .limit(3000)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final registros = snapshot.data!.docs
                .map((d) => _RegistroAuditoria.fromFirestore(d.data() as Map<String, dynamic>))
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Mostrando los últimos 30 días. No es un registro exhaustivo de '
                    'todas las operaciones — cubre cambios de permisos, emisión de '
                    'comprobantes fiscales y anulaciones.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: registros.isEmpty
                      ? const Center(child: Text('No hay eventos registrados en este período.'))
                      : DataExplorer<_RegistroAuditoria>(
                          items: registros,
                          nombreArchivoCsv: 'auditoria',
                          fechaDe: (r) => r.fecha,
                          columnas: [
                            ColumnaExplorador(
                              etiqueta: 'Fecha y Hora',
                              texto: (r) => DateFormat('dd/MM/yyyy HH:mm').format(r.fecha),
                              orden: (r) => r.fecha,
                            ),
                            ColumnaExplorador(etiqueta: 'Usuario', texto: (r) => r.email ?? '-'),
                            ColumnaExplorador(etiqueta: 'Acción', texto: (r) => r.accion),
                            ColumnaExplorador(etiqueta: 'Entidad', texto: (r) => r.entidad),
                            ColumnaExplorador(etiqueta: 'ID', texto: (r) => r.entidadId ?? '-'),
                            ColumnaExplorador(
                              etiqueta: 'Detalle',
                              texto: (r) => r.detalle.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                              visibleInicialmente: false,
                            ),
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
