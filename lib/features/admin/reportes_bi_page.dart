import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../shared/csv_utils.dart';
import '../../shared/csv_download.dart';
import '../../theme/app_theme.dart';

class ReportesBiPage extends StatefulWidget {
  const ReportesBiPage({Key? key}) : super(key: key);

  @override
  State<ReportesBiPage> createState() => _ReportesBiPageState();
}

const String _dimensionMes = '__mes__';
// Métrica sintética para 'cta_cte_proveedores': no es un campo real del
// documento, se calcula como montoHaber - montoDebe (ver
// _procesarYRenderizarReporte).
const String _metricaSaldoProveedor = '__saldo_proveedor__';

class _ReportesBiPageState extends State<ReportesBiPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🏟️ Vista especial de ocupación de canchas por franja horaria — no
  // encaja en el motor genérico de abajo (agrupa por el valor crudo de un
  // campo; acá hace falta expandir cada reserva en las horas que ocupa y
  // calcular un % sobre la capacidad total), así que vive aparte del
  // selector de datasets en vez de ser un dataset más.
  bool _vistaOcupacionCanchas = false;
  Future<Map<String, dynamic>>? _futureOcupacion;

  String _datasetSeleccionado = 'ventas_buffet';
  String _tipoVisualizacion = 'Grafico'; // 'Grafico', 'Tabla', 'Matriz'
  String _dimensionSeleccionada = 'medio_pago';
  String _metricaSeleccionada = 'total';
  String _operacionMetrica = 'Suma'; // 'Suma', 'Promedio', 'Conteo'

  DateTimeRange _rangoFechas = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  Map<String, double>? _ultimosResultados;

  // 🚀 OPTIMIZACIÓN: antes la consulta usaba .snapshots() (listener en
  // tiempo real) para un reporte que se arma una vez y se lee; eso deja un
  // listener abierto que vuelve a bajar TODA la colección filtrada por
  // fecha cada vez que cualquier otro usuario escribe un documento del
  // período, aunque nadie esté mirando el BI en ese momento. Se reemplaza
  // por una consulta puntual (.get()) más un botón de refrescar manual.
  late Future<QuerySnapshot> _futureReporte;

  @override
  void initState() {
    super.initState();
    _futureReporte = _ejecutarConsulta();
  }

  Future<QuerySnapshot> _ejecutarConsulta() {
    final bool esCollectionGroup =
        _configDatasets[_datasetSeleccionado]!['esCollectionGroup'] == true;
    Query query = esCollectionGroup
        ? _firestore.collectionGroup(_datasetSeleccionado)
        : _firestore.collection(_datasetSeleccionado);

    final String? campoFecha =
        _configDatasets[_datasetSeleccionado]!['campoFecha'] as String?;
    if (campoFecha != null) {
      query = query
          .where(campoFecha, isGreaterThanOrEqualTo: _rangoFechas.start)
          .where(
            campoFecha,
            isLessThanOrEqualTo: _rangoFechas.end.add(const Duration(days: 1)),
          );
    }
    return query.get();
  }

  void _recargarReporte() => setState(() {
    if (_vistaOcupacionCanchas) {
      _futureOcupacion = _cargarOcupacionCanchas();
    } else {
      _futureReporte = _ejecutarConsulta();
    }
  });

  // Agrupa las reservas de 'reservas_canchas' del rango elegido por
  // (día de la semana, hora) y calcula qué % de la capacidad disponible
  // (canchas activas × veces que cayó ese día de semana en el rango) se
  // ocupó — para detectar franjas horarias "muertas" para reconvertir.
  Future<Map<String, dynamic>> _cargarOcupacionCanchas() async {
    final ajustesSnap = await _firestore
        .collection('configuraciones_paddle')
        .doc('ajustes_globales')
        .get();
    final int horaApertura =
        (ajustesSnap.data()?['hora_apertura'] as num?)?.toInt() ?? 8;
    final int horaCierre =
        (ajustesSnap.data()?['hora_cierre'] as num?)?.toInt() ?? 23;

    final canchasSnap = await _firestore
        .collection('configuracion_paddle')
        .doc('canchas')
        .get();
    final List<dynamic> listaCanchas =
        (canchasSnap.data()?['lista'] as List?) ?? [];
    // 🚨 Antes caía a 1 cancha en silencio si faltaba la config — eso
    // infla artificialmente el % de ocupación (se divide por 1 en vez de
    // la cantidad real) sin que nada lo indique en la pantalla.
    final bool configCanchasFaltante = listaCanchas.isEmpty;
    final int numCanchas = configCanchasFaltante ? 1 : listaCanchas.length;

    final reservasSnap = await _firestore
        .collection('reservas_canchas')
        .where(
          'fecha',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_rangoFechas.start),
        )
        .where(
          'fecha',
          isLessThanOrEqualTo: Timestamp.fromDate(
            _rangoFechas.end.add(const Duration(days: 1)),
          ),
        )
        .get();

    final Map<int, Map<int, int>> ocupados = {
      for (int d = 1; d <= 7; d++)
        d: {for (int h = horaApertura; h < horaCierre; h++) h: 0},
    };

    // 🚨 Si una reserva tiene una hora fuera de [horaApertura, horaCierre)
    // (por ejemplo el club achicó el horario de apertura después de que ya
    // existieran reservas más tempraneras), antes se descartaba en
    // silencio: el heatmap subestimaba la ocupación real sin avisar nada.
    int horasFueraDeRango = 0;
    for (final doc in reservasSnap.docs) {
      final data = doc.data();
      final Timestamp? ts = data['fecha'] as Timestamp?;
      if (ts == null) continue;
      final int diaSemana = ts.toDate().weekday;
      final int horaInicio = (data['horaInicio'] as num?)?.toInt() ?? 0;
      final int duracion = (data['duracionHoras'] as num?)?.toInt() ?? 1;
      for (int h = horaInicio; h < horaInicio + duracion; h++) {
        if (ocupados[diaSemana]!.containsKey(h)) {
          ocupados[diaSemana]![h] = ocupados[diaSemana]![h]! + 1;
        } else {
          horasFueraDeRango++;
        }
      }
    }

    // Cuántas veces cayó cada día de la semana dentro del rango elegido —
    // así un rango de 10 días no se trata igual que uno de 30 (no se
    // asume "4 semanas" fijo).
    final Map<int, int> ocurrenciasDia = {for (int d = 1; d <= 7; d++) d: 0};
    for (
      DateTime dia = DateTime(
        _rangoFechas.start.year,
        _rangoFechas.start.month,
        _rangoFechas.start.day,
      );
      !dia.isAfter(_rangoFechas.end);
      dia = dia.add(const Duration(days: 1))
    ) {
      ocurrenciasDia[dia.weekday] = (ocurrenciasDia[dia.weekday] ?? 0) + 1;
    }

    return {
      'ocupados': ocupados,
      'ocurrenciasDia': ocurrenciasDia,
      'numCanchas': numCanchas,
      'horaApertura': horaApertura,
      'horaCierre': horaCierre,
      'configCanchasFaltante': configCanchasFaltante,
      'horasFueraDeRango': horasFueraDeRango,
    };
  }

  final Map<String, Map<String, dynamic>> _configDatasets = {
    'ventas_buffet': {
      'nombre': 'Ventas POS / Buffet / Canchas',
      'icono': Icons.point_of_sale_rounded,
      'color': AppColors.teal,
      'campoFecha': 'fecha',
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
    // 🚨 El dataset apuntaba a 'auditoria_compras_facturas', una colección
    // que ningún código del proyecto escribe — las facturas de compra
    // reales se guardan en 'compras_facturas' (nueva_factura_compra_dialog.dart).
    // Los ids de dimensión/métrica de acá abajo también se usan tal cual
    // como nombre de campo de Firestore (ver _procesarYRenderizarReporte),
    // así que además se corrigen para que coincidan con el esquema real del
    // documento (proveedorId→razonSocialProveedor, tipoComprobante,
    // cuitProveedor, montoTotal, netoGravadoTotal, ivaTotal).
    'compras_facturas': {
      'nombre': 'Egresos & Facturas de Compra',
      'icono': Icons.receipt_long_rounded,
      'color': AppColors.warning,
      'campoFecha': 'fechaEmision',
      'dimensiones': [
        {'id': 'razonSocialProveedor', 'label': 'Proveedor'},
        {'id': 'tipoComprobante', 'label': 'Tipo Comprobante Compra'},
        {'id': 'cuitProveedor', 'label': 'CUIT Proveedor'},
      ],
      'metricas': [
        {'id': 'montoTotal', 'label': 'Monto Total (\$)'},
        {'id': 'netoGravadoTotal', 'label': 'Neto Gravado (\$)'},
        {'id': 'ivaTotal', 'label': 'Total IVA (\$)'},
      ],
    },
    // 🚨 'cta_cte_proveedores' es un libro de movimientos (ledger): cada
    // documento tiene 'montoDebe'/'montoHaber' por movimiento (ver
    // orden_pago_dialog.dart, nueva_factura_compra_dialog.dart,
    // nota_credito_debito_compra_dialog.dart), nunca un campo
    // 'saldoDeudaTotal' acumulado — esa métrica siempre daba 0. Se exponen
    // las métricas reales más una métrica sintética "Saldo Deuda"
    // (Haber - Debe por grupo), ver _metricaSaldoProveedor más abajo.
    'cta_cte_proveedores': {
      'nombre': 'Cuentas Corrientes Proveedores',
      'icono': Icons.handshake_rounded,
      'color': AppColors.danger,
      'campoFecha': 'fecha',
      'dimensiones': [
        {'id': 'razonSocial', 'label': 'Razón Social'},
      ],
      'metricas': [
        {'id': _metricaSaldoProveedor, 'label': 'Saldo Deuda (Haber - Debe) (\$)'},
        {'id': 'montoHaber', 'label': 'Facturado (Haber) (\$)'},
        {'id': 'montoDebe', 'label': 'Pagado (Debe) (\$)'},
      ],
    },
    // 👇 NUEVOS DATASETS: antes el BI sólo cubría ventas/compras/proveedores,
    // sin ningún dato de cuotas, socios, asistencias ni profesores.
    'cuenta_corriente': {
      'nombre': 'Cuotas & Movimientos de Socios',
      'icono': Icons.account_balance_wallet_rounded,
      'color': AppColors.info,
      'campoFecha': 'fecha',
      'esCollectionGroup': true, // subcolección socios/{id}/cuenta_corriente
      'dimensiones': [
        {'id': 'tipo', 'label': 'Tipo de Movimiento'},
        {'id': 'estado', 'label': 'Estado (Pendiente/Pagado)'},
        {'id': 'medioPago', 'label': 'Medio de Pago'},
        {'id': 'origen', 'label': 'Origen'},
      ],
      'metricas': [
        {'id': 'monto', 'label': 'Monto (\$)'},
      ],
    },
    'socios': {
      'nombre': 'Padrón de Socios',
      'icono': Icons.groups_rounded,
      'color': AppColors.tealDark,
      'campoFecha': 'fechaAlta',
      'dimensiones': [
        {'id': 'deporte', 'label': 'Actividad'},
        {'id': 'frecuencia', 'label': 'Frecuencia'},
        {'id': 'activo', 'label': 'Activo'},
        {'id': 'esEstudianteEscuela', 'label': 'Convenio Escolar'},
      ],
      'metricas': [
        {'id': 'saldoCuentaCorriente', 'label': 'Saldo Cta. Cte. (\$)'},
      ],
    },
    'asistencias_accesos': {
      'nombre': 'Asistencias & Accesos',
      'icono': Icons.how_to_reg_rounded,
      'color': AppColors.navySoft,
      'campoFecha': 'fechaHora',
      'dimensiones': [
        {'id': 'tipoEntidad', 'label': 'Tipo (Socio/Profesor)'},
        {'id': 'modo', 'label': 'Modo de Acceso'},
      ],
      'metricas': [
        {
          'id': 'creditosRestantes',
          'label': 'Cantidad de Accesos (usar Conteo)',
        },
      ],
    },
    'registro_horas_profes': {
      'nombre': 'Horas de Profesores',
      'icono': Icons.school_rounded,
      'color': AppColors.warning,
      'campoFecha': 'fecha',
      'dimensiones': [
        {'id': 'nombreProfesor', 'label': 'Profesor'},
        {'id': 'actividad', 'label': 'Actividad'},
        {'id': 'liquidado', 'label': 'Liquidado'},
      ],
      'metricas': [
        {'id': 'cantidadHoras', 'label': 'Horas Trabajadas'},
      ],
    },
  };

  Color get _colorDataset =>
      (_configDatasets[_datasetSeleccionado]!['color'] as Color?) ??
      AppColors.teal;

  // Etiqueta legible de la métrica elegida — antes se mostraba el id crudo
  // (p.ej. "__saldo_proveedor__" para la métrica sintética de Saldo Deuda)
  // tanto en el subtítulo como en el CSV exportado.
  String get _etiquetaMetricaActual {
    final metricas =
        _configDatasets[_datasetSeleccionado]!['metricas'] as List;
    final match = metricas.firstWhere(
      (m) => m['id'] == _metricaSeleccionada,
      orElse: () => {'label': _metricaSeleccionada},
    );
    return match['label'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Centro de Reportes & Business Intelligence'),
        actions: [
          IconButton(
            tooltip: 'Actualizar datos',
            onPressed: _recargarReporte,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.tealLight,
              foregroundColor: AppColors.tealDark,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: (_ultimosResultados == null || _vistaOcupacionCanchas)
                ? null
                : _exportarCSV,
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text(
              'Exportar CSV',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🎛️ PANEL IZQUIERDO: CONSTRUCTOR DE CONSULTAS BI
          Container(
            width: 320,
            color: AppColors.surface,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEtiquetaSeccion('Fuente de Datos', Icons.dataset_rounded),
                  const SizedBox(height: AppSpacing.sm),
                  ..._configDatasets.entries.map((e) {
                    final bool sel =
                        !_vistaOcupacionCanchas && e.key == _datasetSeleccionado;
                    final Color color = (e.value['color'] as Color?) ??
                        AppColors.teal;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: () => setState(() {
                          _vistaOcupacionCanchas = false;
                          _datasetSeleccionado = e.key;
                          _dimensionSeleccionada =
                              _configDatasets[e.key]!['dimensiones'][0]['id'];
                          _metricaSeleccionada =
                              _configDatasets[e.key]!['metricas'][0]['id'];
                          _futureReporte = _ejecutarConsulta();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? color.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: sel ? color : AppColors.line,
                              width: sel ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                e.value['icono'] as IconData? ??
                                    Icons.dataset_rounded,
                                size: 18,
                                color: sel ? color : AppColors.textMuted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e.value['nombre'],
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: sel
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (sel)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: color,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  // 🏟️ Ítem aparte (no es un dataset del motor genérico):
                  // ocupación de canchas por franja horaria + alertas de
                  // horarios muertos.
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () => setState(() {
                      _vistaOcupacionCanchas = true;
                      _futureOcupacion = _cargarOcupacionCanchas();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _vistaOcupacionCanchas
                            ? AppColors.info.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: _vistaOcupacionCanchas
                              ? AppColors.info
                              : AppColors.line,
                          width: _vistaOcupacionCanchas ? 1.4 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.grid_on_rounded,
                            size: 18,
                            color: _vistaOcupacionCanchas
                                ? AppColors.info
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ocupación de Canchas (Pádel)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: _vistaOcupacionCanchas
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _vistaOcupacionCanchas
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (_vistaOcupacionCanchas)
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: AppColors.info,
                            ),
                        ],
                      ),
                    ),
                  ),

                  if (!_vistaOcupacionCanchas) ...[
                  const Divider(height: 32),

                  _buildEtiquetaSeccion('Agrupar por', Icons.call_split_rounded),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    value: _dimensionSeleccionada,
                    isExpanded: true,
                    items: [
                      ...(_configDatasets[_datasetSeleccionado]!['dimensiones']
                              as List)
                          .map<DropdownMenuItem<String>>((d) {
                            return DropdownMenuItem(
                              value: d['id'],
                              child: Text(
                                d['label'],
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }),
                      // 📈 Dimensión sintética de tendencia mensual, ofrecida
                      // en cualquier dataset que tenga campo de fecha —
                      // antes no existía forma de ver evolución mes a mes.
                      if (_configDatasets[_datasetSeleccionado]!['campoFecha'] !=
                          null)
                        const DropdownMenuItem(
                          value: _dimensionMes,
                          child: Row(
                            children: [
                              Icon(
                                Icons.show_chart_rounded,
                                size: 15,
                                color: AppColors.teal,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Mes (Tendencia)',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (val) =>
                        setState(() => _dimensionSeleccionada = val!),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  _buildEtiquetaSeccion('Métrica', Icons.functions_rounded),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    value: _metricaSeleccionada,
                    isExpanded: true,
                    items:
                        (_configDatasets[_datasetSeleccionado]!['metricas']
                                as List)
                            .map<DropdownMenuItem<String>>((m) {
                              return DropdownMenuItem(
                                value: m['id'],
                                child: Text(
                                  m['label'],
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            })
                            .toList(),
                    onChanged: (val) =>
                        setState(() => _metricaSeleccionada = val!),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chipOperacion('Suma', Icons.add_rounded),
                      _chipOperacion('Promedio', Icons.balance_rounded),
                      _chipOperacion('Conteo', Icons.tag_rounded),
                    ],
                  ),
                  ],

                  const Divider(height: 32),

                  _buildEtiquetaSeccion('Período', Icons.calendar_month_rounded),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2023),
                        lastDate: DateTime(2030),
                        initialDateRange: _rangoFechas,
                      );
                      if (picked != null) {
                        setState(() {
                          _rangoFechas = picked;
                          if (_vistaOcupacionCanchas) {
                            _futureOcupacion = _cargarOcupacionCanchas();
                          } else {
                            _futureReporte = _ejecutarConsulta();
                          }
                        });
                      }
                    },
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      '${DateFormat('dd/MM/yy').format(_rangoFechas.start)} - ${DateFormat('dd/MM/yy').format(_rangoFechas.end)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),

                  if (!_vistaOcupacionCanchas) ...[
                  const Divider(height: 32),

                  _buildEtiquetaSeccion('Visualización', Icons.insights_rounded),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: _colorDataset.withValues(
                        alpha: 0.12,
                      ),
                      selectedForegroundColor: _colorDataset,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: 'Grafico',
                        icon: Icon(Icons.bar_chart_rounded, size: 16),
                        label: Text('Gráfico'),
                      ),
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
                    ],
                    selected: {_tipoVisualizacion},
                    onSelectionChanged: (set) =>
                        setState(() => _tipoVisualizacion = set.first),
                  ),
                  ],
                ],
              ),
            ),
          ),

          Container(width: 1, color: AppColors.line),

          // 📊 PANEL DERECHO: RESULTADOS & VISUALIZACIÓN DINÁMICA
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _vistaOcupacionCanchas
                  ? _buildVistaOcupacionCanchas()
                  : _procesarYRenderizarReporte(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEtiquetaSeccion(String texto, IconData icono) {
    return Row(
      children: [
        Icon(icono, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          texto.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _chipOperacion(String valor, IconData icono) {
    final bool sel = _operacionMetrica == valor;
    return ChoiceChip(
      selected: sel,
      onSelected: (_) => setState(() => _operacionMetrica = valor),
      avatar: Icon(
        icono,
        size: 15,
        color: sel ? Colors.white : AppColors.textSecondary,
      ),
      label: Text(valor),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: sel ? Colors.white : AppColors.textPrimary,
      ),
      selectedColor: AppColors.navy,
      backgroundColor: AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        side: BorderSide(color: sel ? AppColors.navy : AppColors.line),
      ),
    );
  }

  // =========================================================================
  // 🏟️ OCUPACIÓN DE CANCHAS POR FRANJA HORARIA (+ alertas de horarios muertos)
  // =========================================================================
  Widget _buildVistaOcupacionCanchas() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _futureOcupacion,
      builder: (context, snapshot) {
        // 🚨 Antes sólo chequeaba !hasData: si la consulta fallaba (permisos,
        // red, doc de configuración corrupto), snapshot.hasData quedaba en
        // false para siempre y el admin se quedaba viendo el spinner sin
        // ningún aviso. _procesarYRenderizarReporte ya distinguía este caso.
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'No se pudo calcular la ocupación: ${snapshot.error}',
              style: const TextStyle(color: AppColors.danger),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final datos = snapshot.data!;
        final Map<int, Map<int, int>> ocupados =
            datos['ocupados'] as Map<int, Map<int, int>>;
        final Map<int, int> ocurrenciasDia =
            datos['ocurrenciasDia'] as Map<int, int>;
        final int numCanchas = datos['numCanchas'] as int;
        final int horaApertura = datos['horaApertura'] as int;
        final int horaCierre = datos['horaCierre'] as int;
        final bool configCanchasFaltante = datos['configCanchasFaltante'] as bool;
        final int horasFueraDeRango = datos['horasFueraDeRango'] as int;

        const nombresDias = [
          'Lunes',
          'Martes',
          'Miércoles',
          'Jueves',
          'Viernes',
          'Sábado',
          'Domingo',
        ];

        final Map<int, Map<int, double>> pct = {};
        final List<Map<String, dynamic>> celdas = [];
        for (int d = 1; d <= 7; d++) {
          pct[d] = {};
          final int capacidadDia = (ocurrenciasDia[d] ?? 0) * numCanchas;
          for (int h = horaApertura; h < horaCierre; h++) {
            final int ocup = ocupados[d]?[h] ?? 0;
            // 🚨 Si se achicó la cantidad de canchas activas después de que
            // ya hubiera reservas históricas, numCanchas baja pero 'ocup'
            // sigue contando esas reservas viejas — sin el clamp, el % podía
            // superar 100 y confundir la lectura del heatmap.
            final double p = capacidadDia == 0
                ? 0
                : ((ocup / capacidadDia) * 100).clamp(0, 100);
            pct[d]![h] = p;
            celdas.add({'dia': d, 'hora': h, 'pct': p, 'capacidad': capacidadDia});
          }
        }

        final horariosMuertos =
            celdas.where((c) => (c['capacidad'] as int) > 0 && (c['pct'] as double) < 20).toList()
              ..sort(
                (a, b) => (a['pct'] as double).compareTo(b['pct'] as double),
              );

        Color colorPct(double p) {
          if (p >= 60) return AppColors.success;
          if (p >= 20) return AppColors.warning;
          return AppColors.danger;
        }

        Color colorPctSoft(double p) {
          if (p >= 60) return AppColors.successSoft;
          if (p >= 20) return AppColors.warningSoft;
          return AppColors.dangerSoft;
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEtiquetaSeccion(
                'Ocupación por Día y Horario',
                Icons.grid_on_rounded,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '% de horas-cancha reservadas sobre la capacidad disponible '
                'en el período elegido ($numCanchas cancha/s activa/s).',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (configCanchasFaltante) ...[
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '⚠️ No encontramos la configuración de canchas activas '
                  '(configuracion_paddle/canchas) — se está calculando como '
                  'si hubiera 1 sola cancha, los % pueden estar inflados.',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ],
              if (horasFueraDeRango > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '⚠️ $horasFueraDeRango hora/s reservada/s caen fuera del '
                  'horario configurado ($horaApertura-$horaCierre hs) y no '
                  'se cuentan en este reporte.',
                  style: const TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.line),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(52),
                    children: [
                      TableRow(
                        children: [
                          const SizedBox(width: 74),
                          for (int h = horaApertura; h < horaCierre; h++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Center(
                                child: Text(
                                  '${h}h',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      for (int d = 1; d <= 7; d++)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                nombresDias[d - 1],
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            for (int h = horaApertura; h < horaCierre; h++)
                              Padding(
                                padding: const EdgeInsets.all(2),
                                child: Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: colorPctSoft(pct[d]![h]!),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: colorPct(
                                        pct[d]![h]!,
                                      ).withValues(alpha: 0.4),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${pct[d]![h]!.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: colorPct(pct[d]![h]!),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildEtiquetaSeccion(
                'Horarios Muertos (menos de 20% de ocupación)',
                Icons.warning_amber_rounded,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (horariosMuertos.isEmpty)
                const Text(
                  'No hay horarios por debajo del 20% de ocupación en este '
                  'período — ¡buena noticia!',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    children: horariosMuertos.take(15).map((c) {
                      final String dia = nombresDias[(c['dia'] as int) - 1];
                      return ListTile(
                        leading: const Icon(
                          Icons.schedule_rounded,
                          color: AppColors.danger,
                        ),
                        title: Text('$dia ${c['hora']}:00hs'),
                        trailing: Text(
                          '${(c['pct'] as double).toStringAsFixed(0)}% ocupación',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================================
  // ⚙️ MOTOR DE PROCESAMIENTO BI
  // =========================================================================
  Widget _procesarYRenderizarReporte() {
    // El campo de fecha real de cada dataset (no todos usan 'fecha':
    // compras_facturas usa 'fechaEmision') se vuelve a necesitar acá para
    // la dimensión sintética "Mes" — la consulta en sí ya se ejecutó en
    // _ejecutarConsulta().
    final String? campoFecha =
        _configDatasets[_datasetSeleccionado]!['campoFecha'] as String?;

    return FutureBuilder<QuerySnapshot>(
      future: _futureReporte,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildEstadoVacio(
            icono: Icons.error_outline_rounded,
            color: AppColors.danger,
            titulo: 'Error al consultar datos',
            subtitulo: '${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.teal),
          );
        }

        // 🚫 Los accesos anulados desde el Explorador de Asistencias siguen
        // existiendo como registro (auditoría), pero no deben contar como
        // ingreso real en las métricas de asistencia.
        final docs = snapshot.data!.docs
            .where((d) => (d.data() as Map<String, dynamic>)['anulado'] != true)
            .toList();
        if (docs.isEmpty) {
          return _buildEstadoVacio(
            icono: Icons.query_stats_rounded,
            color: AppColors.textMuted,
            titulo: 'Sin información en este período',
            subtitulo: 'Probá ampliar el rango de fechas o cambiar el dataset.',
          );
        }

        // Agrupamiento Dinámico (Group By) — la dimensión sintética "Mes"
        // (_dimensionMes) no es un campo real: se calcula a partir del
        // campoFecha del dataset (YYYY-MM), para poder ver evolución
        // mensual en cualquier dataset con fecha.
        Map<String, List<double>> agrupado = {};

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;

          String claveDimension;
          if (_dimensionSeleccionada == _dimensionMes && campoFecha != null) {
            final Timestamp? ts = data[campoFecha] as Timestamp?;
            claveDimension = ts != null
                ? DateFormat('yyyy-MM').format(ts.toDate())
                : 'Sin Fecha';
          } else if (_datasetSeleccionado == 'ventas_buffet' &&
              _dimensionSeleccionada == 'tipoComprobante') {
            // 🚨 Esquema mixto: las ventas de POS/caja (la mayoría de los
            // documentos) nunca escriben 'tipoComprobante' — sólo
            // 'tipoComprobanteLegal' (código AFIP, y sólo si se emitió CAE);
            // 'tipoComprobante' como string sólo lo escriben las ventas de
            // inscripcion_torneo_dialog.dart. Agrupar directo por
            // 'tipoComprobante' dejaba casi todo el POS como "Sin
            // Especificar".
            final String? tipoString = data['tipoComprobante'] as String?;
            final dynamic codigoLegal = data['tipoComprobanteLegal'];
            claveDimension = tipoString ??
                (codigoLegal != null
                    ? 'Facturado AFIP (Cód. $codigoLegal)'
                    : 'No Fiscal / Consumo Interno');
          } else {
            final dynamic valorCrudo = data[_dimensionSeleccionada];
            claveDimension = valorCrudo is bool
                ? (valorCrudo ? 'Sí' : 'No')
                : (valorCrudo ?? 'Sin Especificar').toString();
          }
          double valorMetrica = _metricaSeleccionada == _metricaSaldoProveedor
              ? ((data['montoHaber'] as num?)?.toDouble() ?? 0.0) -
                  ((data['montoDebe'] as num?)?.toDouble() ?? 0.0)
              : (data[_metricaSeleccionada] as num?)?.toDouble() ?? 0.0;

          agrupado.putIfAbsent(claveDimension, () => []).add(valorMetrica);
        }

        // Calcular resultado consolidado
        Map<String, double> resultadosConsolidados = {};
        double granTotal = 0;

        final Iterable<String> clavesOrdenadas =
            _dimensionSeleccionada == _dimensionMes
            ? (agrupado.keys.toList()..sort())
            : agrupado.keys;

        for (final clave in clavesOrdenadas) {
          final valores = agrupado[clave]!;
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
        }

        // 🚨 No se puede llamar setState del State padre (_ReportesBiPageState)
        // de forma síncrona acá: este callback corre dentro del build() del
        // StreamBuilder, y Flutter tira "setState() called during build" si
        // se intenta. Se difiere al post-frame para que el botón "Exportar
        // CSV" del AppBar (que vive fuera del StreamBuilder) reaccione.
        //
        // 🐛 BUG REAL que esto corrige: si el usuario cambiaba de dataset
        // (ej. de "Padrón de Socios" a "Asistencias & Accesos") ANTES de que
        // este callback disparara, el resultado viejo (con saldos de cuenta
        // corriente) se aplicaba igual sobre `_ultimosResultados` sin
        // chequear si seguía correspondiendo a la configuración actual —
        // así el CSV exportado (o cualquier otra lectura de
        // `_ultimosResultados`) podía terminar con datos de un reporte
        // completamente distinto al que se veía en pantalla. Ahora se marca
        // con qué configuración se calculó cada resultado, y sólo se aplica
        // si esa configuración sigue siendo la vigente al momento de
        // aplicarlo; si el usuario ya cambió algo, se descarta (la
        // reconstrucción con la nueva configuración ya programó su propia
        // actualización correcta).
        final String firmaCalculo =
            '$_datasetSeleccionado|$_dimensionSeleccionada|$_metricaSeleccionada|'
            '$_operacionMetrica|${_rangoFechas.start}|${_rangoFechas.end}';
        if (!mapEquals(_ultimosResultados, resultadosConsolidados)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final String firmaVigente =
                '$_datasetSeleccionado|$_dimensionSeleccionada|$_metricaSeleccionada|'
                '$_operacionMetrica|${_rangoFechas.start}|${_rangoFechas.end}';
            if (firmaVigente != firmaCalculo) return;
            setState(() => _ultimosResultados = resultadosConsolidados);
          });
        }

        final bool esMoneda = _operacionMetrica != 'Conteo';
        final double promedioGrupo = resultadosConsolidados.isEmpty
            ? 0
            : granTotal / resultadosConsolidados.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _configDatasets[_datasetSeleccionado]!['nombre'],
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Agrupado por ${_dimensionSeleccionada == _dimensionMes ? 'Mes' : _dimensionSeleccionada} · $_operacionMetrica de $_etiquetaMetricaActual',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // 📇 TARJETAS KPI
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Total Consolidado',
                    value: esMoneda
                        ? '\$${NumberFormat('#,##0', 'es_AR').format(granTotal)}'
                        : granTotal.toStringAsFixed(0),
                    icon: Icons.stacked_line_chart_rounded,
                    accent: _colorDataset,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: MetricCard(
                    label: 'Cantidad de Grupos',
                    value: resultadosConsolidados.length.toString(),
                    icon: Icons.category_rounded,
                    accent: AppColors.info,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: MetricCard(
                    label: 'Promedio por Grupo',
                    value: esMoneda
                        ? '\$${NumberFormat('#,##0', 'es_AR').format(promedioGrupo)}'
                        : promedioGrupo.toStringAsFixed(1),
                    icon: Icons.equalizer_rounded,
                    accent: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.line),
                ),
                child: _tipoVisualizacion == 'Tabla'
                    ? _buildVistaTabla(resultadosConsolidados, esMoneda)
                    : _tipoVisualizacion == 'Matriz'
                    ? _buildVistaMatriz(resultadosConsolidados, granTotal, esMoneda)
                    : _dimensionSeleccionada == _dimensionMes
                    ? _buildGraficoLinea(resultadosConsolidados, esMoneda)
                    : _buildGraficoBarras(resultadosConsolidados, esMoneda),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEstadoVacio({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: 36, color: color),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  void _exportarCSV() {
    final datos = _ultimosResultados;
    if (datos == null) return;

    final String etiquetaDimension = _dimensionSeleccionada == _dimensionMes
        ? 'Mes'
        : _dimensionSeleccionada;

    final filas = datos.entries
        .map((e) => [e.key, e.value.toStringAsFixed(2)])
        .toList();

    final csv = generarCsv(
      [etiquetaDimension, '$_operacionMetrica de $_etiquetaMetricaActual'],
      filas,
    );

    try {
      descargarCsv(
        'reporte_bi_${_datasetSeleccionado}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
        csv,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
      }
    }
  }

  String _formatearValor(double valor, bool esMoneda) {
    return esMoneda
        ? '\$${NumberFormat('#,##0', 'es_AR').format(valor)}'
        : valor.toStringAsFixed(valor == valor.roundToDouble() ? 0 : 1);
  }

  // 1️⃣ VISTA TABLA DINÁMICA
  Widget _buildVistaTabla(Map<String, double> datos, bool esMoneda) {
    final entradas = datos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.separated(
      itemCount: entradas.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.line),
      itemBuilder: (context, i) {
        final entry = entradas[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                _formatearValor(entry.value, esMoneda),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _colorDataset,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 2️⃣ VISTA MATRIZ CON PORCENTAJES DE PARTICIPACIÓN
  Widget _buildVistaMatriz(
    Map<String, double> datos,
    double granTotal,
    bool esMoneda,
  ) {
    final entradas = datos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 🚨 Con la métrica sintética de saldo (puede dar negativo), granTotal
    // consolidado puede terminar en 0 o negativo aunque sí haya datos
    // reales — el chequeo "granTotal > 0" descartaba ese caso entero y
    // mostraba 0% en todos los grupos. Si pasa, se usa la suma de valores
    // absolutos como base de participación.
    final double denominador = granTotal > 0
        ? granTotal
        : entradas.fold(0.0, (s, e) => s + e.value.abs());

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.1,
      ),
      itemCount: entradas.length,
      itemBuilder: (context, i) {
        final entry = entradas[i];
        final porcentaje = denominador > 0
            ? (entry.value / denominador) * 100
            : 0.0;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry.key,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatearValor(entry.value, esMoneda),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _colorDataset,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _colorDataset.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '${porcentaje.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _colorDataset,
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

  // 3️⃣ GRÁFICO DE BARRAS (fl_chart) — reemplaza las barras de porcentaje
  // hechas a mano por un gráfico real, con eje, grilla y tooltip al tocar.
  Widget _buildGraficoBarras(Map<String, double> datos, bool esMoneda) {
    final entradas = datos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final double maxValor = entradas.fold(
      0.0,
      (max, e) => e.value > max ? e.value : max,
    );

    final double anchoBarra = entradas.length <= 6 ? 36 : 24;
    final double anchoContenido = (entradas.length * (anchoBarra + 28))
        .clamp(300, double.infinity)
        .toDouble();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: anchoContenido,
        child: BarChart(
          BarChartData(
            // 🚨 Si todos los grupos dan 0 en la métrica elegida (ej.
            // "Promedio" de un campo que ningún documento del período
            // tiene cargado), maxY quedaba en 0 — fl_chart degenera con
            // minY/maxY iguales y puede romper el layout del gráfico.
            // _buildGraficoLinea ya tenía este resguardo, acá faltaba.
            maxY: maxValor == 0 ? 1 : maxValor * 1.2,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxValor > 0 ? maxValor / 4 : 1,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: AppColors.line, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.navy,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final entry = entradas[group.x.toInt()];
                  return BarTooltipItem(
                    '${entry.key}\n',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text: _formatearValor(entry.value, esMoneda),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 52,
                  getTitlesWidget: (value, meta) => Text(
                    esMoneda
                        ? NumberFormat.compact(locale: 'es_AR').format(value)
                        : value.toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    final int i = value.toInt();
                    if (i < 0 || i >= entradas.length) {
                      return const SizedBox.shrink();
                    }
                    final String etiqueta = entradas[i].key;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Transform.rotate(
                        angle: -0.4,
                        child: Text(
                          etiqueta.length > 12
                              ? '${etiqueta.substring(0, 12)}…'
                              : etiqueta,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (int i = 0; i < entradas.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: entradas[i].value,
                      color: _colorDataset,
                      width: anchoBarra,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxValor * 1.2,
                        color: AppColors.surfaceMuted,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 4️⃣ GRÁFICO DE LÍNEA (fl_chart) — usado específicamente para la
  // dimensión "Mes (Tendencia)", donde una serie temporal se lee mejor como
  // línea que como barras.
  Widget _buildGraficoLinea(Map<String, double> datos, bool esMoneda) {
    final entradas = datos.entries.toList(); // ya vienen ordenadas por mes
    final double maxValor = entradas.fold(
      0.0,
      (max, e) => e.value > max ? e.value : max,
    );

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxValor == 0 ? 1 : maxValor * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxValor > 0 ? maxValor / 4 : 1,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.navy,
            getTooltipItems: (spots) => spots.map((s) {
              final entry = entradas[s.x.toInt()];
              return LineTooltipItem(
                '${entry.key}\n${_formatearValor(entry.value, esMoneda)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, meta) => Text(
                esMoneda
                    ? NumberFormat.compact(locale: 'es_AR').format(value)
                    : value.toStringAsFixed(0),
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final int i = value.toInt();
                if (i < 0 || i >= entradas.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    entradas[i].key,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < entradas.length; i++)
                FlSpot(i.toDouble(), entradas[i].value),
            ],
            isCurved: true,
            color: _colorDataset,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                    radius: 4,
                    color: _colorDataset,
                    strokeColor: Colors.white,
                    strokeWidth: 2,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _colorDataset.withValues(alpha: 0.22),
                  _colorDataset.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
