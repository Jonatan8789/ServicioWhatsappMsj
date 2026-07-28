import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class LibroIvaComprasPage extends StatefulWidget {
  const LibroIvaComprasPage({super.key});

  @override
  State<LibroIvaComprasPage> createState() => _LibroIvaComprasPageState();
}

class _LibroIvaComprasPageState extends State<LibroIvaComprasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Selección de Período
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Libro IVA Compras & Percepciones',
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
            onPressed: () => _exportarCSV(context),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text(
              'Exportar a CSV / Excel',
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
            // 🗓️ BARRA DE FILTRO POR PERÍODO
            _buildBarraPeriodo(),
            const SizedBox(height: 20),

            // 📊 STREAMBUILDER CON CÁLCULO EN TIEMPO REAL
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('compras_facturas')
                    .where(
                      'fechaEmision',
                      isGreaterThanOrEqualTo: Timestamp.fromDate(_fechaInicio),
                    )
                    .where(
                      'fechaEmision',
                      isLessThanOrEqualTo: Timestamp.fromDate(
                        _fechaFin.add(const Duration(days: 1)),
                      ),
                    )
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error al cargar datos: ${snapshot.error}'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;

                  // 🧮 ACUMULADORES CONTABLES
                  double acumuladoNeto21 = 0.0;
                  double acumuladoNeto105 = 0.0;
                  double acumuladoNeto27 = 0.0;
                  double acumuladoNetoTotal = 0.0;
                  double acumuladoIvaTotal = 0.0;
                  double acumuladoExento = 0.0;
                  double acumuladoPercepIIBB = 0.0;
                  double acumuladoPercepIVA = 0.0;
                  double acumuladoPercepGan = 0.0;
                  double acumuladoTotalComprobantes = 0.0;

                  for (var doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    acumuladoNeto21 +=
                        (data['netoGravado21'] as num?)?.toDouble() ?? 0.0;
                    acumuladoNeto105 +=
                        (data['netoGravado105'] as num?)?.toDouble() ?? 0.0;
                    acumuladoNeto27 +=
                        (data['netoGravado27'] as num?)?.toDouble() ?? 0.0;
                    acumuladoNetoTotal +=
                        (data['netoGravadoTotal'] as num?)?.toDouble() ?? 0.0;
                    acumuladoIvaTotal +=
                        (data['ivaTotal'] as num?)?.toDouble() ?? 0.0;
                    acumuladoExento +=
                        (data['exento'] as num?)?.toDouble() ?? 0.0;
                    acumuladoPercepIIBB +=
                        (data['percepcionIIBBTotal'] as num?)?.toDouble() ??
                        (data['percepcionIIBB'] as num?)?.toDouble() ??
                        0.0;
                    acumuladoPercepIVA +=
                        (data['percepcionIVA'] as num?)?.toDouble() ?? 0.0;
                    acumuladoPercepGan +=
                        (data['percepcionGanancias'] as num?)?.toDouble() ??
                        0.0;
                    acumuladoTotalComprobantes +=
                        (data['montoTotal'] as num?)?.toDouble() ?? 0.0;
                  }

                  return Column(
                    children: [
                      // TARJETAS RESUMEN DE TOTALES IMPOSITIVOS
                      _buildTarjetasResumen(
                        neto: acumuladoNetoTotal,
                        iva: acumuladoIvaTotal,
                        percepciones:
                            acumuladoPercepIIBB +
                            acumuladoPercepIVA +
                            acumuladoPercepGan,
                        exento: acumuladoExento,
                        total: acumuladoTotalComprobantes,
                      ),
                      const SizedBox(height: 20),

                      // TABLA DETALLADA DEL LIBRO IVA COMPRAS
                      Expanded(
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: docs.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No hay comprobantes cargados en el período seleccionado.',
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
                                              'Comprobante',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Razon Social',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'CUIT',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Neto 21%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Neto 10.5%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Neto 27%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Total IVA',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Exento',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Perc. IIBB',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Perc. IVA/Gan',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: Text(
                                              'Total Comprobante',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                        rows: docs.map((doc) {
                                          final data =
                                              doc.data()
                                                  as Map<String, dynamic>;
                                          final DateTime fecha =
                                              (data['fechaEmision']
                                                      as Timestamp)
                                                  .toDate();
                                          final double n21 =
                                              (data['netoGravado21'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          final double n105 =
                                              (data['netoGravado105'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          final double n27 =
                                              (data['netoGravado27'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          final double ivaT =
                                              (data['ivaTotal'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          final double ex =
                                              (data['exento'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          final double pIIBB =
                                              (data['percepcionIIBBTotal']
                                                      as num?)
                                                  ?.toDouble() ??
                                              (data['percepcionIIBB'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          final double pOtras =
                                              ((data['percepcionIVA'] as num?)
                                                      ?.toDouble() ??
                                                  0.0) +
                                              ((data['percepcionGanancias']
                                                          as num?)
                                                      ?.toDouble() ??
                                                  0.0);
                                          final double totalComp =
                                              (data['montoTotal'] as num?)
                                                  ?.toDouble() ??
                                              0.0;

                                          return DataRow(
                                            cells: [
                                              DataCell(
                                                Text(
                                                  DateFormat(
                                                    'dd/MM/yyyy',
                                                  ).format(fecha),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  '${data['tipoComprobante']} ${data['numeroComprobante']}',
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  data['razonSocialProveedor'] ??
                                                      '-',
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  data['cuitProveedor'] ?? '-',
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  _currencyFormat.format(n21),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  _currencyFormat.format(n105),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  _currencyFormat.format(n27),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  _currencyFormat.format(ivaT),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue,
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  _currencyFormat.format(ex),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  _currencyFormat.format(pIIBB),
                                                  style: const TextStyle(
                                                    color: Colors.orange,
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  _currencyFormat.format(
                                                    pOtras,
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  _currencyFormat.format(
                                                    totalComp,
                                                  ),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🗓️ WIDGET BARRA DE PERÍODO
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
          const Icon(Icons.calendar_month_rounded, color: Colors.teal),
          const SizedBox(width: 10),
          Text(
            'Período: ${DateFormat('dd/MM/yyyy').format(_fechaInicio)} al ${DateFormat('dd/MM/yyyy').format(_fechaFin)}',
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

  // 🎴 WIDGET TARJETAS RESUMEN IMPOSITIVO
  Widget _buildTarjetasResumen({
    required double neto,
    required double iva,
    required double percepciones,
    required double exento,
    required double total,
  }) {
    return Row(
      children: [
        _tarjetaTotal('Neto Gravado', neto, Colors.teal),
        const SizedBox(width: 12),
        _tarjetaTotal('Crédito Fiscal IVA', iva, Colors.blue),
        const SizedBox(width: 12),
        _tarjetaTotal('Percepciones (IIBB/Nac)', percepciones, Colors.orange),
        const SizedBox(width: 12),
        _tarjetaTotal('Exento / No Gravado', exento, Colors.grey),
        const SizedBox(width: 12),
        _tarjetaTotal('TOTAL COMPRAS', total, Colors.teal, esDestacado: true),
      ],
    );
  }

  Widget _tarjetaTotal(
    String titulo,
    double monto,
    MaterialColor color, {
    bool esDestacado = false,
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
                _currencyFormat.format(monto),
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

  // 📥 SIMULACIÓN DE EXPORTACIÓN CSV
  void _exportarCSV(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Generando archivo Libro_IVA_Compras.csv para descarga...',
        ),
        backgroundColor: Colors.teal,
      ),
    );
  }
}
