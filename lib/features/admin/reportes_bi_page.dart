import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ReportesBiPage extends StatefulWidget {
  const ReportesBiPage({Key? key}) : super(key: key);

  @override
  State<ReportesBiPage> createState() => _ReportesBiPageState();
}

class _ReportesBiPageState extends State<ReportesBiPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1️⃣ DATASET SELECCIONADO
  String _datasetSeleccionado = 'ventas_buffet';

  // 2️⃣ MODO DE VISUALIZACIÓN
  String _tipoVisualizacion = 'Tabla'; // 'Tabla', 'Matriz', 'GraficoBarras'

  // 3️⃣ CONFIGURACIÓN DE CONSULTA (DIMENSIONES Y MÉTRICAS)
  String _dimensionSeleccionada = 'medio_pago'; // Campo por el cual agrupar
  String _metricaSeleccionada = 'total'; // Campo numérico a calcular
  String _operacionMetrica = 'Suma'; // 'Suma', 'Promedio', 'Conteo'

  // 4️⃣ FILTROS DE FECHA
  DateTimeRange _rangoFechas = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  bool _cargando = false;

  // Mapa de configuraciones según Dataset
  final Map<String, Map<String, dynamic>> _configDatasets = {
    'ventas_buffet': {
      'nombre': 'Ventas POS / Buffet / Canchas',
      'dimensiones': [
        {'id': 'medio_pago', 'label': 'Medio de Pago'},
        {'id': 'tipoComprobante', 'label': 'Tipo Comprobante'},
        {'id': 'usuario', 'label': 'Operador / Cajero'},
        {'id': 'origen_salón', 'label': 'Origen / Mesa'},
      ],
      'metricas': [
        {'id': 'total', 'label': 'Monto Total (\$)'},
      ],
    },
    'auditoria_compras_facturas': {
      'nombre': 'Egresos & Facturas de Compra',
      'dimensiones': [
        {'id': 'proveedor', 'label': 'Proveedor'},
        {'id': 'tipo', 'label': 'Tipo Comprobante Compra'},
        {'id': 'cuit', 'label': 'CUIT Proveedor'},
      ],
      'metricas': [
        {'id': 'total', 'label': 'Monto Total (\$)'},
        {'id': 'neto', 'label': 'Neto Gravado (\$)'},
        {'id': 'iva', 'label': 'Total IVA (\$)'},
      ],
    },
    'cta_cte_proveedores': {
      'nombre': 'Cuentas Corrientes Proveedores',
      'dimensiones': [
        {'id': 'razonSocial', 'label': 'Razón Social'},
      ],
      'metricas': [
        {'id': 'saldoDeudaTotal', 'label': 'Saldo Deuda (\$)'},
      ],
    },
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Centro de Reportes & Business Intelligence (BI)'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🎛️ PANEL IZQUIERDO: CONSTRUCTOR DE CONSULTAS BI
          Container(
            width: 320,
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Fuente de Datos (Dataset)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _datasetSeleccionado,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _configDatasets.entries.map((e) {
                      return DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          e.value['nombre'],
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _datasetSeleccionado = val!;
                        // Reseteamos dimensión y métrica al cambiar dataset
                        _dimensionSeleccionada =
                            _configDatasets[_datasetSeleccionado]!['dimensiones'][0]['id'];
                        _metricaSeleccionada =
                            _configDatasets[_datasetSeleccionado]!['metricas'][0]['id'];
                      });
                    },
                  ),

                  const Divider(height: 32),

                  const Text(
                    '2. Eje / Dimensión (Agrupar por)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _dimensionSeleccionada,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items:
                        (_configDatasets[_datasetSeleccionado]!['dimensiones']
                                as List)
                            .map<DropdownMenuItem<String>>((d) {
                              return DropdownMenuItem(
                                value: d['id'],
                                child: Text(d['label']),
                              );
                            })
                            .toList(),
                    onChanged: (val) =>
                        setState(() => _dimensionSeleccionada = val!),
                  ),

                  const Divider(height: 32),

                  const Text(
                    '3. Métrica & Operación',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _metricaSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Campo Valor',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items:
                        (_configDatasets[_datasetSeleccionado]!['metricas']
                                as List)
                            .map<DropdownMenuItem<String>>((m) {
                              return DropdownMenuItem(
                                value: m['id'],
                                child: Text(m['label']),
                              );
                            })
                            .toList(),
                    onChanged: (val) =>
                        setState(() => _metricaSeleccionada = val!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _operacionMetrica,
                    decoration: const InputDecoration(
                      labelText: 'Cálculo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Suma',
                        child: Text('Suma Total'),
                      ),
                      DropdownMenuItem(
                        value: 'Promedio',
                        child: Text('Promedio / Ticket Promedios'),
                      ),
                      DropdownMenuItem(
                        value: 'Conteo',
                        child: Text('Cantidad de Operaciones'),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _operacionMetrica = val!),
                  ),

                  const Divider(height: 32),

                  const Text(
                    '4. Filtro Temporada / Fecha',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                    ),
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2023),
                        lastDate: DateTime(2030),
                        initialDateRange: _rangoFechas,
                      );
                      if (picked != null) {
                        setState(() => _rangoFechas = picked);
                      }
                    },
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      '${DateFormat('dd/MM/yy').format(_rangoFechas.start)} - ${DateFormat('dd/MM/yy').format(_rangoFechas.end)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),

                  const Divider(height: 32),

                  const Text(
                    '5. Formato de Salida',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'Tabla',
                        icon: Icon(Icons.table_chart_rounded, size: 16),
                        label: Text('Tabla'),
                      ),
                      ButtonSegment(
                        value: 'Matriz',
                        icon: Icon(Icons.grid_on_rounded, size: 16),
                        label: Text('Matriz'),
                      ),
                      ButtonSegment(
                        value: 'GraficoBarras',
                        icon: Icon(Icons.bar_chart_rounded, size: 16),
                        label: Text('Gráfico'),
                      ),
                    ],
                    selected: {_tipoVisualizacion},
                    onSelectionChanged: (set) =>
                        setState(() => _tipoVisualizacion = set.first),
                  ),
                ],
              ),
            ),
          ),

          Container(width: 1, color: Colors.grey.shade300),

          // 📊 PANEL DERECHO: RENDIMIENTO & VISUALIZACIÓN DINÁMICA
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _procesarYRenderizarReporte(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ⚙️ MOTOR DE PROCESAMIENTO BI
  // =========================================================================
  Widget _procesarYRenderizarReporte() {
    Query query = _firestore.collection(_datasetSeleccionado);

    // Aplicar filtro de fecha si el dataset lo soporta
    if (_datasetSeleccionado != 'cta_cte_proveedores') {
      query = query
          .where('fecha', isGreaterThanOrEqualTo: _rangoFechas.start)
          .where(
            'fecha',
            isLessThanOrEqualTo: _rangoFechas.end.add(const Duration(days: 1)),
          );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error al consultar datos: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No hay información disponible para el rango seleccionado.',
            ),
          );
        }

        // Agrupamiento Dinámico (Group By)
        Map<String, List<double>> agrupado = {};

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;

          String claveDimension =
              (data[_dimensionSeleccionada] ?? 'Sin Especificar').toString();
          double valorMetrica =
              (data[_metricaSeleccionada] as num?)?.toDouble() ?? 0.0;

          if (!agrupado.containsKey(claveDimension)) {
            agrupado[claveDimension] = [];
          }
          agrupado[claveDimension]!.add(valorMetrica);
        }

        // Calcular resultado consolidado
        Map<String, double> resultadosConsolidados = {};
        double granTotal = 0;

        agrupado.forEach((clave, valores) {
          double res = 0;
          if (_operacionMetrica == 'Suma') {
            res = valores.fold(0, (a, b) => a + b);
          } else if (_operacionMetrica == 'Promedio') {
            res = valores.isEmpty
                ? 0
                : valores.fold(0.0, (a, b) => a + b) / valores.length;
          } else if (_operacionMetrica == 'Conteo') {
            res = valores.length.toDouble();
          }
          resultadosConsolidados[clave] = res;
          granTotal += res;
        });

        // 🎨 RENDERIZADO SEGÚN LA OPCIÓN SELECCIONADA
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reporte BI: ${_configDatasets[_datasetSeleccionado]!['nombre']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Agrupado por: $_dimensionSeleccionada | Cálculo: $_operacionMetrica de $_metricaSeleccionada',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'GRAN TOTAL CONSOLIDADO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      Text(
                        _operacionMetrica == 'Conteo'
                            ? granTotal.toStringAsFixed(0)
                            : '\$${granTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            Expanded(
              child: _tipoVisualizacion == 'Tabla'
                  ? _buildVistaTabla(resultadosConsolidados)
                  : _tipoVisualizacion == 'Matriz'
                  ? _buildVistaMatriz(resultadosConsolidados, granTotal)
                  : _buildVistaGraficoBarras(resultadosConsolidados),
            ),
          ],
        );
      },
    );
  }

  // 1️⃣ VISTA TABLA DINÁMICA
  Widget _buildVistaTabla(Map<String, double> datos) {
    return ListView(
      children: [
        DataTable(
          columns: [
            DataColumn(
              label: Text(
                _dimensionSeleccionada.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'VALOR CALCULADO ($_operacionMetrica)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: datos.entries.map((entry) {
            return DataRow(
              cells: [
                DataCell(Text(entry.key)),
                DataCell(
                  Text(
                    _operacionMetrica == 'Conteo'
                        ? entry.value.toStringAsFixed(0)
                        : '\$${entry.value.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  // 2️⃣ VISTA MATRIZ CON PORCENTAJES DE PARTICIPACIÓN
  Widget _buildVistaMatriz(Map<String, double> datos, double granTotal) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.2,
      ),
      itemCount: datos.length,
      itemBuilder: (context, i) {
        final entry = datos.entries.elementAt(i);
        final porcentaje = granTotal > 0
            ? (entry.value / granTotal) * 100
            : 0.0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry.key,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _operacionMetrica == 'Conteo'
                        ? entry.value.toStringAsFixed(0)
                        : '\$${entry.value.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.indigo,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${porcentaje.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // 3️⃣ VISTA GRÁFICO VISUAL NATIVO EN BARRAS PORCENTUALES
  Widget _buildVistaGraficoBarras(Map<String, double> datos) {
    double maxValor = datos.values.fold(0, (max, v) => v > max ? v : max);
    if (maxValor == 0) maxValor = 1;

    return ListView.builder(
      itemCount: datos.length,
      itemBuilder: (context, i) {
        final entry = datos.entries.elementAt(i);
        final porcentajeAncho = entry.value / maxValor;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _operacionMetrica == 'Conteo'
                        ? entry.value.toStringAsFixed(0)
                        : '\$${entry.value.toStringAsFixed(2)}',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FractionallySizedBox(
                widthFactor: porcentajeAncho > 0 ? porcentajeAncho : 0.02,
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
