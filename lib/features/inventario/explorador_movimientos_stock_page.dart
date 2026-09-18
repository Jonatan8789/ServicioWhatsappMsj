import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../shared/data_explorer.dart';
import '../../theme/app_theme.dart';

class _MovimientoStock {
  final String productoNombre;
  final String tipo;
  final int cantidad;
  final String? referencia;
  final String? usuario;
  final DateTime fecha;

  _MovimientoStock({
    required this.productoNombre,
    required this.tipo,
    required this.cantidad,
    required this.fecha,
    this.referencia,
    this.usuario,
  });

  factory _MovimientoStock.fromFirestore(Map<String, dynamic> data) {
    return _MovimientoStock(
      productoNombre: data['productoNombre']?.toString() ?? '?',
      tipo: data['tipo']?.toString() ?? '?',
      cantidad: (data['cantidad'] as num?)?.toInt() ?? 0,
      referencia: data['referencia']?.toString(),
      usuario: data['usuario']?.toString(),
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Explorador de movimientos de stock — antes no existía ningún historial
/// auditable de por qué bajó/subió el stock de un producto, sólo el número
/// actual. Lee de 'movimientos_stock', que ahora alimentan tanto el POS
/// (ventas) como la edición manual en Central de Inventario (ajustes).
class ExploradorMovimientosStockPage extends StatelessWidget {
  const ExploradorMovimientosStockPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Movimientos de Stock')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('movimientos_stock')
              .orderBy('fecha', descending: true)
              .limit(2000)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final movimientos = snapshot.data!.docs
                .map(
                  (d) => _MovimientoStock.fromFirestore(
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .toList();

            if (movimientos.isEmpty) {
              return const Center(
                child: Text(
                  'Todavía no hay movimientos registrados.\n'
                  'Van a empezar a aparecer con la próxima venta o ajuste manual de stock.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            return DataExplorer<_MovimientoStock>(
              items: movimientos,
              nombreArchivoCsv: 'movimientos_stock',
              fechaDe: (m) => m.fecha,
              columnas: [
                ColumnaExplorador(
                  etiqueta: 'Fecha',
                  texto: (m) => DateFormat('dd/MM/yyyy HH:mm').format(m.fecha),
                  orden: (m) => m.fecha,
                ),
                ColumnaExplorador(
                  etiqueta: 'Producto',
                  texto: (m) => m.productoNombre,
                ),
                ColumnaExplorador(etiqueta: 'Tipo', texto: (m) => m.tipo),
                ColumnaExplorador(
                  etiqueta: 'Cantidad',
                  texto: (m) => m.cantidad > 0 ? '+${m.cantidad}' : '${m.cantidad}',
                  orden: (m) => m.cantidad,
                ),
                ColumnaExplorador(
                  etiqueta: 'Usuario',
                  texto: (m) => m.usuario ?? '-',
                ),
                ColumnaExplorador(
                  etiqueta: 'Referencia',
                  texto: (m) => m.referencia ?? '-',
                  visibleInicialmente: false,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
