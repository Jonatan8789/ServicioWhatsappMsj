import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import 'cancha_padel_repository.dart';

/// Reportes de BI específicos de pádel: ocupación de canchas, ingresos
/// desglosados (alquiler / Pro-Shop / clases), turnos fijos activos y
/// alumnos por profesor — todo en una sola pantalla, en vez de tener que
/// armarlo a mano desde el BI genérico de Administración (pensado para
/// datasets fiscales/contables, no para este desglose puntual de pádel).
///
/// Mismo criterio que reportes_bi_page.dart: consultas puntuales (.get(),
/// no .snapshots()) con un botón de refrescar manual — un reporte que se
/// arma una vez y se lee no necesita un listener en tiempo real.
class ReportesBiPadelPage extends StatefulWidget {
  const ReportesBiPadelPage({super.key});

  @override
  State<ReportesBiPadelPage> createState() => _ReportesBiPadelPageState();
}

class _ReportesBiPadelPageState extends State<ReportesBiPadelPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTimeRange _rango = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  late Future<_ReportePadel> _futureReporte;

  @override
  void initState() {
    super.initState();
    _futureReporte = _generarReporte();
  }

  Future<_ReportePadel> _generarReporte() async {
    final inicio = DateTime(_rango.start.year, _rango.start.month, _rango.start.day);
    final fin = DateTime(_rango.end.year, _rango.end.month, _rango.end.day)
        .add(const Duration(days: 1));
    final int cantidadDias = fin.difference(inicio).inDays;

    final ajustesSnap = await _firestore
        .collection('configuraciones_paddle')
        .doc('ajustes_globales')
        .get();
    final int horaApertura = (ajustesSnap.data()?['hora_apertura'] as num?)?.toInt() ?? 8;
    final int horaCierre = (ajustesSnap.data()?['hora_cierre'] as num?)?.toInt() ?? 23;

    final nombresCanchas = await obtenerNombresCanchasActivas(_firestore);
    final int numCanchas = nombresCanchas.isEmpty ? 1 : nombresCanchas.length;

    final reservasSnap = await _firestore
        .collection('reservas_canchas')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThan: Timestamp.fromDate(fin))
        .get();

    final clasesSnap = await _firestore
        .collection('clases_padel')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThan: Timestamp.fromDate(fin))
        .get();

    final pagosClasesSnap = await _firestore
        .collection('pagos_clases_padel')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThan: Timestamp.fromDate(fin))
        .get();

    final turnosCanchaSnap = await _firestore
        .collection('turnos_recurrentes_canchas')
        .where('activo', isEqualTo: true)
        .get();
    final turnosClaseSnap = await _firestore
        .collection('turnos_recurrentes_clases_padel')
        .where('activo', isEqualTo: true)
        .get();

    // --- Ocupación ---
    int horasOcupadas = 0;
    double ingresosAlquiler = 0;
    double ingresosProShop = 0;
    final Map<String, int> horasPorCancha = {};
    for (final doc in reservasSnap.docs) {
      final d = doc.data();
      final duracion = (d['duracionHoras'] as num?)?.toInt() ?? 1;
      final cancha = d['cancha']?.toString() ?? '-';
      horasOcupadas += duracion;
      horasPorCancha[cancha] = (horasPorCancha[cancha] ?? 0) + duracion;

      final metodoPago = d['metodoPago']?.toString();
      if (metodoPago != 'Clase de Pádel') {
        ingresosAlquiler += (d['precio'] as num?)?.toDouble() ?? 0;
      }
      for (final item in (d['itemsProShop'] as List?) ?? const []) {
        final m = item as Map<String, dynamic>;
        final cantidad = (m['cantidad'] as num?)?.toInt() ?? 0;
        final precioUnitario = (m['precioUnitario'] as num?)?.toDouble() ?? 0;
        ingresosProShop += cantidad * precioUnitario;
      }
    }
    final int capacidadTotal = numCanchas * (horaCierre - horaApertura) * cantidadDias;
    final double pctOcupacion =
        capacidadTotal == 0 ? 0 : (horasOcupadas / capacidadTotal * 100).clamp(0, 100);

    // --- Ingresos de clases (sólo lo efectivamente cobrado) ---
    double ingresosClases = 0;
    for (final doc in pagosClasesSnap.docs) {
      final d = doc.data();
      final cobrado = d['cobrado'] == true || d['estadoPagoMP'] == 'Aprobado';
      if (cobrado) ingresosClases += (d['monto'] as num?)?.toDouble() ?? 0;
    }

    // --- Alumnos por profesor (de las clases del período, inscriptos únicos) ---
    final Map<String, _ProfesorAlumnos> porProfesor = {};
    for (final doc in clasesSnap.docs) {
      final d = doc.data();
      final profesorId = d['profesorId']?.toString() ?? '-';
      final profesorNombre = d['profesorNombre']?.toString() ?? 'Sin profesor';
      final entry = porProfesor.putIfAbsent(
        profesorId,
        () => _ProfesorAlumnos(nombre: profesorNombre),
      );
      entry.clases++;
      for (final id in (d['inscriptosIds'] as List?) ?? const []) {
        entry.alumnosUnicos.add(id.toString());
      }
    }

    return _ReportePadel(
      cantidadDias: cantidadDias,
      numCanchas: numCanchas,
      horasOcupadas: horasOcupadas,
      pctOcupacion: pctOcupacion,
      horasPorCancha: horasPorCancha,
      ingresosAlquiler: ingresosAlquiler,
      ingresosProShop: ingresosProShop,
      ingresosClases: ingresosClases,
      turnosFijosCancha: turnosCanchaSnap.size,
      turnosFijosClase: turnosClaseSnap.size,
      porProfesor: porProfesor.values.toList()
        ..sort((a, b) => b.alumnosUnicos.length.compareTo(a.alumnosUnicos.length)),
    );
  }

  void _recargar() => setState(() => _futureReporte = _generarReporte());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reportes BI · Pádel'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Elegir período',
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: _rango,
                firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) {
                setState(() => _rango = picked);
                _recargar();
              }
            },
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _recargar,
          ),
        ],
      ),
      body: FutureBuilder<_ReportePadel>(
        future: _futureReporte,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'No se pudo calcular el reporte: ${snapshot.error}',
                style: const TextStyle(color: AppColors.danger),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Período: ${_fmt(_rango.start)} — ${_fmt(_rango.end)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildCardOcupacion(r),
                const SizedBox(height: AppSpacing.lg),
                _buildCardIngresos(r),
                const SizedBox(height: AppSpacing.lg),
                _buildCardTurnosFijos(r),
                const SizedBox(height: AppSpacing.lg),
                _buildCardAlumnosPorProfesor(r),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _card({required String titulo, required IconData icono, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                titulo.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  letterSpacing: 0.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _buildCardOcupacion(_ReportePadel r) {
    return _card(
      titulo: 'Ocupación de canchas',
      icono: Icons.grid_on_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r.pctOcupacion.toStringAsFixed(1)}% ocupado',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          Text(
            '${r.horasOcupadas} hora/s reservadas en ${r.numCanchas} cancha/s activa/s '
            'sobre ${r.cantidadDias} día/s.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const Divider(height: AppSpacing.lg),
          ...r.horasPorCancha.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key),
                  Text('${e.value} hs', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (r.horasPorCancha.isEmpty)
            const Text('Sin reservas en este período.', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _filaMonto(String label, double monto, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '\$${monto.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildCardIngresos(_ReportePadel r) {
    final total = r.ingresosAlquiler + r.ingresosProShop + r.ingresosClases;
    return _card(
      titulo: 'Ingresos (sólo lo cobrado)',
      icono: Icons.payments_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\$${total.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          _filaMonto('Alquiler de cancha', r.ingresosAlquiler, AppColors.teal),
          _filaMonto('Pro-Shop (paletas/pelotas)', r.ingresosProShop, AppColors.info),
          _filaMonto('Clases de pádel', r.ingresosClases, AppColors.tealDark),
          const SizedBox(height: 4),
          const Text(
            'El alquiler de cancha sólo cuenta reservas que no son clases '
            '(las clases se cobran por alumno, no por la cancha en sí).',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTurnosFijos(_ReportePadel r) {
    return _card(
      titulo: 'Turnos fijos activos',
      icono: Icons.event_repeat_rounded,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.turnosFijosCancha}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const Text('De cancha (abonos)', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.turnosFijosClase}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const Text('Clases recurrentes', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardAlumnosPorProfesor(_ReportePadel r) {
    return _card(
      titulo: 'Alumnos por profesor (clases del período)',
      icono: Icons.school_rounded,
      child: r.porProfesor.isEmpty
          ? const Text('Sin clases en este período.', style: TextStyle(color: AppColors.textSecondary))
          : Column(
              children: r.porProfesor.map((p) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(p.nombre)),
                      Text(
                        '${p.alumnosUnicos.length} alumno/s · ${p.clases} clase/s',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _ProfesorAlumnos {
  final String nombre;
  int clases = 0;
  final Set<String> alumnosUnicos = {};
  _ProfesorAlumnos({required this.nombre});
}

class _ReportePadel {
  final int cantidadDias;
  final int numCanchas;
  final int horasOcupadas;
  final double pctOcupacion;
  final Map<String, int> horasPorCancha;
  final double ingresosAlquiler;
  final double ingresosProShop;
  final double ingresosClases;
  final int turnosFijosCancha;
  final int turnosFijosClase;
  final List<_ProfesorAlumnos> porProfesor;

  _ReportePadel({
    required this.cantidadDias,
    required this.numCanchas,
    required this.horasOcupadas,
    required this.pctOcupacion,
    required this.horasPorCancha,
    required this.ingresosAlquiler,
    required this.ingresosProShop,
    required this.ingresosClases,
    required this.turnosFijosCancha,
    required this.turnosFijosClase,
    required this.porProfesor,
  });
}
