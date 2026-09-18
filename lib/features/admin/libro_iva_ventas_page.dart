import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../shared/csv_utils.dart';
import '../../shared/csv_download.dart';

class _VentaFiscal {
  final DateTime fecha;
  final String origen;
  final String concepto;
  final String medioPago;
  final String? cae;
  final double monto;

  _VentaFiscal({
    required this.fecha,
    required this.origen,
    required this.concepto,
    required this.medioPago,
    required this.cae,
    required this.monto,
  });
}

/// Libro IVA Ventas — antes leía de 'ventas_facturas', una colección que
/// ningún flujo del sistema escribe (quedaba siempre vacía). Los
/// comprobantes fiscales reales con CAE se generan en dos lugares:
/// ventas_buffet (POS + inscripciones de torneo, campo 'fiscalizado') y
/// socios/{id}/cuenta_corriente (cobro de cuota social, campo
/// 'facturadoArca'). Esta pantalla ahora une ambos. No se muestra un
/// desglose de neto/IVA por alícuota porque la facturación ARCA del club
/// se emite como Monotributista (Factura C, sin discriminar IVA) — mostrar
/// esa columna con datos inventados sería peor que no mostrarla.
class LibroIvaVentasPage extends StatefulWidget {
  const LibroIvaVentasPage({super.key});

  @override
  State<LibroIvaVentasPage> createState() => _LibroIvaVentasPageState();
}

class _LibroIvaVentasPageState extends State<LibroIvaVentasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _fechaInicio = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  DateTime _fechaFin = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'es_AR',
    symbol: '\$',
  );

  List<_VentaFiscal>? _ultimaListaCargada;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Libro IVA Ventas (Comprobantes con CAE)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _ultimaListaCargada == null
                ? null
                : () => _exportarCSV(context, _ultimaListaCargada!),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text(
              'Exportar CSV',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildBarraPeriodo(),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('ventas_buffet')
                    .where('fiscalizado', isEqualTo: true)
                    .where(
                      'fecha',
                      isGreaterThanOrEqualTo: Timestamp.fromDate(_fechaInicio),
                    )
                    .where(
                      'fecha',
                      isLessThanOrEqualTo: Timestamp.fromDate(
                        _fechaFin.add(const Duration(days: 1)),
                      ),
                    )
                    .snapshots(),
                builder: (context, snapshotVentas) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collectionGroup('cuenta_corriente')
                        .where('facturadoArca', isEqualTo: true)
                        .where(
                          'fecha',
                          isGreaterThanOrEqualTo: Timestamp.fromDate(
                            _fechaInicio,
                          ),
                        )
                        .where(
                          'fecha',
                          isLessThanOrEqualTo: Timestamp.fromDate(
                            _fechaFin.add(const Duration(days: 1)),
                          ),
                        )
                        .snapshots(),
                    builder: (context, snapshotCuotas) {
                      if (snapshotVentas.hasError || snapshotCuotas.hasError) {
                        return Center(
                          child: Text(
                            'Error al cargar comprobantes: ${snapshotVentas.error ?? snapshotCuotas.error}',
                          ),
                        );
                      }
                      if (!snapshotVentas.hasData || !snapshotCuotas.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final List<_VentaFiscal> lista = [];

                      for (var doc in snapshotVentas.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final Timestamp? t = data['fecha'] as Timestamp?;
                        if (t == null) continue;
                        final List items = data['items'] ?? [];
                        final String detalle = items.isNotEmpty
                            ? items
                                  .map((it) => '${it['cantidad']}x ${it['nombre']}')
                                  .join(' | ')
                            : 'Venta POS / Buffet';
                        lista.add(
                          _VentaFiscal(
                            fecha: t.toDate(),
                            origen: 'POS / Buffet / Torneo',
                            concepto: detalle,
                            medioPago: data['medio_pago']?.toString() ?? '-',
                            cae: data['cae']?.toString(),
                            monto: (data['total'] as num?)?.toDouble() ?? 0.0,
                          ),
                        );
                      }

                      for (var doc in snapshotCuotas.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final Timestamp? t = data['fecha'] as Timestamp?;
                        if (t == null) continue;
                        lista.add(
                          _VentaFiscal(
                            fecha: t.toDate(),
                            origen: 'Cuota Social',
                            concepto:
                                data['concepto']?.toString() ??
                                data['tipo']?.toString() ??
                                'Cobro de Cuota',
                            medioPago: data['medioPago']?.toString() ?? '-',
                            cae: data['cae']?.toString(),
                            monto: ((data['monto'] as num?)?.toDouble() ?? 0.0)
                                .abs(),
                          ),
                        );
                      }

                      lista.sort((a, b) => b.fecha.compareTo(a.fecha));

                      // 🚨 No se puede llamar setState del State padre de
                      // forma síncrona acá (este callback corre dentro del
                      // build() de un StreamBuilder anidado): se difiere al
                      // post-frame para que el botón "Exportar CSV" del
                      // AppBar reaccione una vez que llegan datos reales.
                      if (_ultimaListaCargada?.length != lista.length) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() => _ultimaListaCargada = lista);
                          }
                        });
                      } else {
                        _ultimaListaCargada = lista;
                      }

                      final double totalFacturado = lista.fold(
                        0.0,
                        (acc, v) => acc + v.monto,
                      );

                      return Column(
                        children: [
                          _buildTarjetasResumen(
                            total: totalFacturado,
                            cantidad: lista.length,
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: lista.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No hay comprobantes fiscales (con CAE) emitidos en el período seleccionado.',
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: DataTable(
                                            headingRowColor:
                                                WidgetStateProperty.all(
                                                  const Color(0xFFF1F5F9),
                                                ),
                                            columns: const [
                                              DataColumn(
                                                label: Text(
                                                  'Fecha',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Origen',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Concepto',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Medio de Pago',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'CAE',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Monto',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            rows: lista.map((v) {
                                              return DataRow(
                                                cells: [
                                                  DataCell(
                                                    Text(
                                                      DateFormat(
                                                        'dd/MM/yyyy HH:mm',
                                                      ).format(v.fecha),
                                                    ),
                                                  ),
                                                  DataCell(Text(v.origen)),
                                                  DataCell(
                                                    ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                            maxWidth: 280,
                                                          ),
                                                      child: Text(
                                                        v.concepto,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(Text(v.medioPago)),
                                                  DataCell(
                                                    Text(v.cae ?? '-'),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      _currencyFormat.format(
                                                        v.monto,
                                                      ),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraPeriodo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, color: Colors.indigo),
          const SizedBox(width: 10),
          Text(
            'Período Ventas: ${DateFormat('dd/MM/yyyy').format(_fechaInicio)} al ${DateFormat('dd/MM/yyyy').format(_fechaFin)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range_rounded),
            label: const Text('Cambiar Período'),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: DateTimeRange(
                  start: _fechaInicio,
                  end: _fechaFin,
                ),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() {
                  _fechaInicio = picked.start;
                  _fechaFin = picked.end;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetasResumen({required double total, required int cantidad}) {
    return Row(
      children: [
        _tarjetaTotal('Comprobantes Emitidos', cantidad.toDouble(), Colors.blueGrey, esMoneda: false),
        const SizedBox(width: 12),
        _tarjetaTotal('TOTAL FACTURADO (CAE)', total, Colors.teal, esDestacado: true),
      ],
    );
  }

  Widget _tarjetaTotal(
    String titulo,
    double valor,
    MaterialColor color, {
    bool esDestacado = false,
    bool esMoneda = true,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: esDestacado ? color.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: esDestacado ? color.shade900 : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: esDestacado ? Colors.white70 : Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                esMoneda ? _currencyFormat.format(valor) : valor.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: esDestacado ? Colors.white : color.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportarCSV(BuildContext context, List<_VentaFiscal> lista) {
    final filas = lista
        .map(
          (v) => [
            DateFormat('dd/MM/yyyy HH:mm').format(v.fecha),
            v.origen,
            v.concepto,
            v.medioPago,
            v.cae ?? '',
            v.monto.toStringAsFixed(2),
          ],
        )
        .toList();

    final csv = generarCsv(
      ['Fecha', 'Origen', 'Concepto', 'Medio de Pago', 'CAE', 'Monto'],
      filas,
    );

    try {
      descargarCsv(
        'libro_iva_ventas_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
        csv,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }
}
