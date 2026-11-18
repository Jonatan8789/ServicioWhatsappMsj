import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../shared/data_explorer.dart';
import '../../theme/app_theme.dart';
import '../../services/auditoria_service.dart';

class _RegistroAcceso {
  final String id;
  final String nombre;
  final String dni;
  final String tipoEntidad;
  final String modo;
  final DateTime fechaHora;
  final bool anulado;
  final String? motivoAnulacion;

  _RegistroAcceso({
    required this.id,
    required this.nombre,
    required this.dni,
    required this.tipoEntidad,
    required this.modo,
    required this.fechaHora,
    required this.anulado,
    this.motivoAnulacion,
  });

  factory _RegistroAcceso.fromFirestore(String id, Map<String, dynamic> data) {
    return _RegistroAcceso(
      id: id,
      nombre: data['nombreSocio']?.toString() ?? 'Usuario',
      dni: data['dniSocio']?.toString() ?? 'S/D',
      tipoEntidad: data['tipoEntidad']?.toString() ?? 'Socio',
      modo: data['modo']?.toString() ?? '-',
      fechaHora: (data['fechaHora'] as Timestamp?)?.toDate() ?? DateTime.now(),
      anulado: data['anulado'] == true,
      motivoAnulacion: data['motivoAnulacion']?.toString(),
    );
  }
}

/// Explorador histórico de asistencias/accesos — antes el único lugar para
/// ver ingresos era el "Monitor Acceso en Vivo" de Control de Acceso, que
/// sólo muestra el día de hoy y no tiene búsqueda ni exportación. Éste lee
/// toda la colección 'asistencias_accesos' (socios + profesores) con rango
/// de fechas real, y permite anular ingresos mal registrados (huella
/// cruzada, doble marcado, error de kiosco) sin borrar el registro —
/// queda como auditoría, sólo deja de contar como asistencia real.
class ExploradorAsistenciasPage extends StatefulWidget {
  const ExploradorAsistenciasPage({super.key});

  @override
  State<ExploradorAsistenciasPage> createState() =>
      _ExploradorAsistenciasPageState();
}

class _ExploradorAsistenciasPageState extends State<ExploradorAsistenciasPage> {
  Future<void> _anularRegistro(_RegistroAcceso registro) async {
    final motivoCtrl = TextEditingController();
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Ingreso'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${registro.nombre} (DNI ${registro.dni}) — '
              '${DateFormat('dd/MM/yyyy HH:mm').format(registro.fechaHora)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('¿Confirmás que este ingreso quedó mal registrado?'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('asistencias_accesos')
          .doc(registro.id)
          .update({
            'anulado': true,
            'motivoAnulacion': motivoCtrl.text.trim(),
            'anuladoPor': FirebaseAuth.instance.currentUser?.email ?? 'admin',
            'fechaAnulacion': DateTime.now(),
          });
      await registrarAuditoria(
        accion: 'anular_ingreso_asistencia',
        entidad: 'asistencias_accesos',
        entidadId: registro.id,
        detalle: {
          'nombre': registro.nombre,
          'dni': registro.dni,
          'motivo': motivoCtrl.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ingreso anulado.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error al anular: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restaurarRegistro(_RegistroAcceso registro) async {
    await FirebaseFirestore.instance
        .collection('asistencias_accesos')
        .doc(registro.id)
        .update({'anulado': false, 'motivoAnulacion': FieldValue.delete()});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('↩️ Ingreso restaurado.'), backgroundColor: Colors.blue),
      );
    }
  }

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
                    d.id,
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
                            ColumnaExplorador(
                              etiqueta: 'Estado',
                              texto: (r) => r.anulado ? 'ANULADO' : 'Válido',
                            ),
                          ],
                          accionesFila: (context, r) => r.anulado
                              ? IconButton(
                                  tooltip: 'Restaurar ingreso',
                                  icon: const Icon(Icons.restore_rounded, color: Colors.blue, size: 20),
                                  onPressed: () => _restaurarRegistro(r),
                                )
                              : IconButton(
                                  tooltip: 'Anular ingreso mal registrado',
                                  icon: const Icon(Icons.block_rounded, color: Colors.red, size: 20),
                                  onPressed: () => _anularRegistro(r),
                                ),
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
