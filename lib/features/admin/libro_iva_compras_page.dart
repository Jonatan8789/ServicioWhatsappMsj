import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../shared/csv_utils.dart';
import '../../shared/csv_download.dart';
import '../../shared/libro_iva_digital_export.dart';

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

  List<QueryDocumentSnapshot<Object?>>? _ultimaListaCargada;
  bool _exportandoLibroIva = false;

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
            onPressed: _ultimaListaCargada == null
                ? null
                : () => _exportarCSV(context, _ultimaListaCargada!),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text(
              'Exportar a CSV / Excel',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            onPressed: _ultimaListaCargada == null || _exportandoLibroIva
                ? null
                : () => _exportarLibroIvaDigital(context, _ultimaListaCargada!),
            icon: _exportandoLibroIva
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.description_outlined, size: 20),
            label: const Text(
              'Libro IVA Digital (TXT)',
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

                  // 🚨 Igual que en libro_iva_ventas_page.dart: no se puede
                  // llamar setState del State padre de forma síncrona acá
                  // (corre dentro del build() del StreamBuilder) — se
                  // difiere al post-frame para que el botón "Exportar CSV"
                  // del AppBar reaccione cuando llegan datos reales.
                  //
                  // 🐛 Antes comparaba sólo por longitud: si el usuario
                  // cambiaba el rango de fechas mientras el callback estaba
                  // en cola, se podía exportar una lista de un período
                  // distinto al que se ve en pantalla. Ahora sólo se aplica
                  // si el rango con el que se calculó sigue vigente.
                  final DateTime fechaInicioCalculo = _fechaInicio;
                  final DateTime fechaFinCalculo = _fechaFin;
                  if (_ultimaListaCargada?.length != docs.length) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (_fechaInicio != fechaInicioCalculo ||
                          _fechaFin != fechaFinCalculo) {
                        return;
                      }
                      setState(() => _ultimaListaCargada = docs);
                    });
                  } else {
                    _ultimaListaCargada = docs;
                  }

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
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      // 📱 Debajo de este ancho la tabla de
                                      // ~12 columnas sólo se veía vía scroll
                                      // horizontal, ilegible: se reemplaza
                                      // por una lista de tarjetas.
                                      if (constraints.maxWidth < 700) {
                                        return _buildListaTarjetas(docs);
                                      }
                                      return SingleChildScrollView(
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
                                  );
                                    },
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

  // 📱 Vista de tarjetas para pantallas angostas — reemplaza la tabla de
  // ~12 columnas que sólo se veía haciendo scroll horizontal. Muestra los
  // campos principales siempre visibles y el resto (desgloses por
  // alícuota/percepción) en un bloque secundario más chico debajo.
  Widget _buildListaTarjetas(List<QueryDocumentSnapshot> docs) {
    return ListView.separated(
      itemCount: docs.length,
      separatorBuilder: (_, __) => const Divider(height: 20),
      itemBuilder: (context, i) {
        final data = docs[i].data() as Map<String, dynamic>;
        final DateTime fecha = (data['fechaEmision'] as Timestamp).toDate();
        final double totalComp = (data['montoTotal'] as num?)?.toDouble() ?? 0.0;
        final double ivaT = (data['ivaTotal'] as num?)?.toDouble() ?? 0.0;
        final double pIIBB =
            (data['percepcionIIBBTotal'] as num?)?.toDouble() ??
            (data['percepcionIIBB'] as num?)?.toDouble() ??
            0.0;
        final double pOtras =
            ((data['percepcionIVA'] as num?)?.toDouble() ?? 0.0) +
            ((data['percepcionGanancias'] as num?)?.toDouble() ?? 0.0);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('dd/MM/yyyy').format(fecha),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    _currencyFormat.format(totalComp),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                data['razonSocialProveedor'] ?? '-',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${data['tipoComprobante'] ?? ''} ${data['numeroComprobante'] ?? ''} • CUIT ${data['cuitProveedor'] ?? '-'}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'IVA: ${_currencyFormat.format(ivaT)}',
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                  if (pIIBB > 0)
                    Text(
                      'Perc. IIBB: ${_currencyFormat.format(pIIBB)}',
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  if (pOtras > 0)
                    Text(
                      'Perc. IVA/Gan: ${_currencyFormat.format(pOtras)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ],
          ),
        );
      },
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

  // 🧾 EXPORT LIBRO DE IVA DIGITAL (formato ARCA, ex-CITI) — ver
  // lib/shared/libro_iva_digital_export.dart para la especificación de
  // campos. Sólo incluye Factura A/B con CAE del proveedor discriminado;
  // 'Ticket X'/'Interno' no son comprobantes fiscales de compra y no
  // forman parte del Libro de IVA.
  Future<void> _exportarLibroIvaDigital(
    BuildContext context,
    List<QueryDocumentSnapshot<Object?>> docs,
  ) async {
    setState(() => _exportandoLibroIva = true);
    try {
      final List<ComprobanteCompraIva> comprobantes = [];

      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final String tipoTexto = data['tipoComprobante']?.toString() ?? '';
        final int? codigoTipo = codigoComprobantePorTexto(tipoTexto);
        if (codigoTipo == null) continue; // Ticket X / Interno / etc.

        final String numeroCompleto = data['numeroComprobante']?.toString() ?? '';
        final partes = numeroCompleto.split('-');
        if (partes.length != 2) continue; // formato inesperado, se omite

        final int? puntoVenta = int.tryParse(partes[0]);
        final int? numero = int.tryParse(partes[1]);
        if (puntoVenta == null || numero == null) continue;

        final DateTime? fecha = (data['fechaEmision'] as Timestamp?)?.toDate();
        if (fecha == null) continue;

        final double n21 = (data['netoGravado21'] as num?)?.toDouble() ?? 0.0;
        final double n105 = (data['netoGravado105'] as num?)?.toDouble() ?? 0.0;
        final double n27 = (data['netoGravado27'] as num?)?.toDouble() ?? 0.0;

        comprobantes.add(
          ComprobanteCompraIva(
            fecha: fecha,
            tipoComprobante: codigoTipo,
            puntoVenta: puntoVenta,
            numero: numero,
            cuitProveedor: data['cuitProveedor']?.toString() ?? '',
            razonSocialProveedor: data['razonSocialProveedor']?.toString() ?? '',
            total: (data['montoTotal'] as num?)?.toDouble() ?? 0.0,
            exento: (data['exento'] as num?)?.toDouble() ?? 0.0,
            percepcionIVA: (data['percepcionIVA'] as num?)?.toDouble() ?? 0.0,
            percepcionGanancias: (data['percepcionGanancias'] as num?)?.toDouble() ?? 0.0,
            percepcionIIBB: (data['percepcionIIBBTotal'] as num?)?.toDouble() ??
                (data['percepcionIIBB'] as num?)?.toDouble() ??
                0.0,
            creditoFiscal: (data['ivaTotal'] as num?)?.toDouble() ?? 0.0,
            netoPorAlicuota: {21.0: n21, 10.5: n105, 27.0: n27},
          ),
        );
      }

      if (comprobantes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No hay comprobantes Factura A/B con formato de N° válido '
                '(PPPP-NNNNNNNN) en este período.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final String sufijo = DateFormat('yyyy-MM').format(_fechaInicio);
      descargarCsv('LIBRO_IVA_DIGITAL_COMPRAS_CBTE_$sufijo.txt', generarComprasCbte(comprobantes));
      descargarCsv('LIBRO_IVA_DIGITAL_COMPRAS_ALICUOTAS_$sufijo.txt', generarComprasAlicuotas(comprobantes));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Generados ${comprobantes.length} comprobante(s) — revisá los campos antes de importarlos al Portal IVA.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el Libro de IVA: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportandoLibroIva = false);
    }
  }

  // 📥 EXPORTACIÓN CSV REAL — antes esto era un stub que sólo mostraba un
  // SnackBar y no generaba ningún archivo.
  void _exportarCSV(
    BuildContext context,
    List<QueryDocumentSnapshot<Object?>> docs,
  ) {
    final filas = docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final DateTime fecha = (data['fechaEmision'] as Timestamp).toDate();
      return [
        DateFormat('dd/MM/yyyy').format(fecha),
        '${data['tipoComprobante'] ?? ''} ${data['numeroComprobante'] ?? ''}',
        data['razonSocialProveedor'] ?? '',
        data['cuitProveedor'] ?? '',
        ((data['netoGravado21'] as num?) ?? 0).toStringAsFixed(2),
        ((data['netoGravado105'] as num?) ?? 0).toStringAsFixed(2),
        ((data['netoGravado27'] as num?) ?? 0).toStringAsFixed(2),
        ((data['ivaTotal'] as num?) ?? 0).toStringAsFixed(2),
        ((data['exento'] as num?) ?? 0).toStringAsFixed(2),
        (((data['percepcionIIBBTotal'] as num?) ??
                    (data['percepcionIIBB'] as num?)) ??
                0)
            .toStringAsFixed(2),
        (((data['percepcionIVA'] as num?) ?? 0) +
                ((data['percepcionGanancias'] as num?) ?? 0))
            .toStringAsFixed(2),
        ((data['montoTotal'] as num?) ?? 0).toStringAsFixed(2),
      ];
    }).toList();

    final csv = generarCsv(
      [
        'Fecha',
        'Comprobante',
        'Razón Social',
        'CUIT',
        'Neto 21%',
        'Neto 10.5%',
        'Neto 27%',
        'Total IVA',
        'Exento',
        'Perc. IIBB',
        'Perc. IVA/Ganancias',
        'Total Comprobante',
      ],
      filas,
    );

    try {
      descargarCsv(
        'libro_iva_compras_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
        csv,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }
}
