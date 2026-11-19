import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:natatorio_app/features/admin/proveedores_compras_page.dart';
import 'package:natatorio_app/features/admin/reportes_bi_page.dart';
import 'package:natatorio_app/features/buffet/explorador_ventas_page.dart';
import 'package:natatorio_app/features/inventario/inventario_general_page.dart';
import 'package:natatorio_app/features/inventario/inventario_general_model.dart';
import 'package:natatorio_app/features/paddle/canchas_page.dart';
import 'package:natatorio_app/features/natatorio/andariveles_page.dart';
import 'package:natatorio_app/features/paddle/admin_partidos_abiertos_page.dart';
import 'package:natatorio_app/features/gimnasio/gestion_clases_gimnasio_page.dart';
import 'package:natatorio_app/features/gimnasio/asignar_rutina_page.dart';
import 'package:natatorio_app/features/admin/sitio_web_page.dart';
import 'package:natatorio_app/features/profesores/profesores_page.dart';
import '../auth/auth_services.dart';
import '../auth/login_page.dart';
import '../admin/usuarios_page.dart';
import '../admin/configuracion_page.dart';
import '../admin/tesoreria_page.dart';
import '../admin/tesoreria_libros_iva_page.dart';
import '../admin/admin_fiscal_config_page.dart';
import '../admin/liquidacion_cuotas_page.dart';
import '../socios/alta_socio_page.dart';
import '../socios/socios_page.dart';
import '../socios/socio_detalle_page.dart';
import '../socios/editar_socio_page.dart';
import '../tarifas/tarifas_page.dart';
import '../profesores/cronogramas_page.dart';
import '../asistencias/nomina_diaria_page.dart';
import '../asistencias/control_acceso_page.dart';
import '../mensajeria/mensajeria_page.dart';
import 'package:natatorio_app/features/paddle/configuracion_paddle_page.dart';
import 'package:natatorio_app/features/paddle/gestion_clases_padel_page.dart';
import 'package:natatorio_app/features/paddle/turnos_fijos_padel_page.dart';
import 'package:natatorio_app/features/paddle/reportes_bi_padel_page.dart';
import '../buffet/pos_caja_page.dart';
import '../buffet/monitor_cocina_page.dart';
import '../buffet/menu_buffet_page.dart';
import 'package:natatorio_app/features/paddle/crear_torneo_page.dart';
import 'package:natatorio_app/features/paddle/detalle_torneo_page.dart';
import '../socios/socio_dashboard_page.dart';
import '../profesores/liquidacion_profesores_page.dart';
import '../../theme/app_theme.dart';
import '../inventario/explorador_movimientos_stock_page.dart';
import '../asistencias/explorador_asistencias_page.dart';
import '../admin/auditoria_page.dart';
import '../admin/panel_riesgo_bajas_page.dart';

// 🎾 NUEVA IMPORTACIÓN DEL EXPLORADOR DE RESERVAS
import 'package:natatorio_app/features/paddle/explorador_reservas_page.dart';

class DashboardPage extends StatefulWidget {
  final String rolUsuario;

  const DashboardPage({super.key, required this.rolUsuario});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _userActual = FirebaseAuth.instance.currentUser;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Widget _pantallaActual;
  String _filtroMenu = "";

  // 📱 Debajo de este ancho el panel lateral fijo de 264px no entra en un
  // celular: se reemplaza por un Drawer que se abre con el ícono hamburguesa.
  static const double _anchoBreakpointMovil = 900;

  @override
  void initState() {
    super.initState();
    _pantallaActual = _construirPanelInicio();
  }

  Widget _construirPanelInicio() {
    final DateTime ahora = DateTime.now();
    final int horaActual = ahora.hour;

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('socios')
                  .where('usuarioUid', isEqualTo: _userActual?.uid ?? '')
                  .limit(1)
                  .snapshots(),
              builder: (context, snapshot) {
                String nombreMostrar = widget.rolUsuario == 'admin'
                    ? 'Administrador'
                    : 'Socio';

                if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                  final dataSocio =
                      snapshot.data!.docs.first.data() as Map<String, dynamic>;
                  nombreMostrar = dataSocio['nombre'] ?? nombreMostrar;
                }

                return Text(
                  '¡Bienvenido de nuevo, $nombreMostrar!',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                );
              },
            ),
            Text(
              'Estado operativo del club para hoy (${ahora.day}/${ahora.month}/${ahora.year}).',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 30),

            Row(
              children: [
                // 💸 Antes las 4 tarjetas de abajo streameaban en vivo la
                // colección ENTERA de socios/asistencias/reservas sólo para
                // sacar un número — cualquier escritura a cualquier socio
                // (un pago, un check-in) recargaba esa lectura completa acá
                // Y en cualquier otra pantalla que tuviera el mismo listener
                // abierto, todo el tiempo que este panel de Inicio quedara
                // montado (que puede ser todo el día). Ahora son consultas
                // puntuales (FutureBuilder, no StreamBuilder) que se piden
                // una sola vez al entrar a "Inicio" — volver a entrar al
                // menú refresca los números.
                FutureBuilder<AggregateQuerySnapshot>(
                  future: _firestore.collection('socios').count().get(),
                  builder: (context, snapshot) {
                    final String total = snapshot.hasData
                        ? (snapshot.data!.count ?? 0).toString()
                        : '...';
                    return _buildMetricCard(
                      'Socios Registrados',
                      total,
                      Icons.supervised_user_circle_rounded,
                      Colors.blue.shade700,
                      const Color(0xFFF0F9FF),
                    );
                  },
                ),
                const SizedBox(width: 16),

                FutureBuilder<QuerySnapshot>(
                  future: _firestore.collection('socios').get(),
                  builder: (context, snapshot) {
                    String cuotasAlDia = '...';
                    if (snapshot.hasData) {
                      final mesActualClave =
                          "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}";

                      final alDia = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final ultimoMes = data['ultimoMesPago'] ?? '';
                        return ultimoMes == mesActualClave ||
                            data['estadoCuota'] == 'AL_DIA';
                      }).length;

                      cuotasAlDia = "$alDia / ${snapshot.data!.docs.length}";
                    }

                    return _buildMetricCard(
                      'Cuotas al Día',
                      cuotasAlDia,
                      Icons.verified_user_rounded,
                      Colors.green.shade700,
                      const Color(0xFFF0FDF4),
                    );
                  },
                ),
                const SizedBox(width: 16),

                FutureBuilder<AggregateQuerySnapshot>(
                  future: _firestore
                      .collection('asistencias_accesos')
                      .where(
                        'fechaStr',
                        isEqualTo:
                            "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}",
                      )
                      .count()
                      .get(),
                  builder: (context, snapshot) {
                    final String presentismoHoy = snapshot.hasData
                        ? (snapshot.data!.count ?? 0).toString()
                        : '...';
                    return _buildMetricCard(
                      'Presentismo Hoy',
                      '$presentismoHoy ingresos',
                      Icons.fingerprint_rounded,
                      Colors.purple.shade700,
                      const Color(0xFFFAF5FF),
                    );
                  },
                ),
                const SizedBox(width: 16),

                FutureBuilder<AggregateQuerySnapshot>(
                  future: _firestore
                      .collection('reservas_canchas')
                      .where(
                        'fecha',
                        isGreaterThanOrEqualTo: Timestamp.fromDate(
                          DateTime(ahora.year, ahora.month, ahora.day),
                        ),
                      )
                      .where(
                        'fecha',
                        isLessThan: Timestamp.fromDate(
                          DateTime(ahora.year, ahora.month, ahora.day).add(const Duration(days: 1)),
                        ),
                      )
                      .count()
                      .get(),
                  builder: (context, snapshot) {
                    String porcentaje = '...';
                    if (snapshot.hasData) {
                      final int deHoy = snapshot.data!.count ?? 0;
                      double calculo = (deHoy / 45) * 100;
                      porcentaje = "${calculo.toStringAsFixed(0)}%";
                    }
                    return _buildMetricCard(
                      'Ocupación Canchas',
                      porcentaje,
                      Icons.analytics_rounded,
                      Colors.orange.shade700,
                      const Color(0xFFFFF7ED),
                    );
                  },
                ),

                if (widget.rolUsuario == 'admin') ...[
                  const SizedBox(width: 16),
                  StreamBuilder<QuerySnapshot>(
                    // 🚨 No tenía filtro de fecha: sumaba TODA la historia de
                    // ventas, no el total de hoy que el título sugiere.
                    stream: _firestore
                        .collection('ventas_buffet')
                        .where(
                          'fecha',
                          isGreaterThanOrEqualTo: DateTime(
                            DateTime.now().year,
                            DateTime.now().month,
                            DateTime.now().day,
                          ),
                        )
                        .snapshots(),
                    builder: (context, snapshot) {
                      double totalDiario = 0.0;
                      if (snapshot.hasData) {
                        for (var doc in snapshot.data!.docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          totalDiario +=
                              (data['total'] as num?)?.toDouble() ?? 0.0;
                        }
                      }
                      return _buildMetricCard(
                        'Caja Buffet Hoy',
                        '\$${totalDiario.toStringAsFixed(0)}',
                        Icons.account_balance_wallet_rounded,
                        Colors.teal.shade700,
                        const Color.fromARGB(255, 200, 209, 203),
                      );
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 40),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF0F172A,
                          ).withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.sports_tennis_rounded,
                              color: Color(0xFF1E293B),
                              size: 22,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Próximos Turnos del Día',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        StreamBuilder<QuerySnapshot>(
                          // 🚨 Antes escuchaba TODA la colección
                          // 'reservas_canchas' (la historia completa de
                          // turnos, para siempre) sólo para filtrar en
                          // memoria los del día de hoy — cada reserva nueva
                          // de CUALQUIER día disparaba este listener y
                          // re-sincronizaba todo el historial. Acotado al
                          // día de hoy con el mismo campo 'fecha' que ya usa
                          // el resto de las pantallas de pádel.
                          stream: _firestore
                              .collection('reservas_canchas')
                              .where(
                                'fecha',
                                isGreaterThanOrEqualTo: Timestamp.fromDate(
                                  DateTime(ahora.year, ahora.month, ahora.day),
                                ),
                              )
                              .where(
                                'fecha',
                                isLessThan: Timestamp.fromDate(
                                  DateTime(
                                    ahora.year,
                                    ahora.month,
                                    ahora.day,
                                  ).add(const Duration(days: 1)),
                                ),
                              )
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: LinearProgressIndicator(),
                              );
                            }

                            final turnosFuturos = snapshot.data!.docs
                                .map(
                                  (doc) => doc.data() as Map<String, dynamic>,
                                )
                                .where((r) {
                                  final int rInicio = r['horaInicio'] ?? 0;
                                  return rInicio >= horaActual;
                                })
                                .toList();

                            turnosFuturos.sort(
                              (a, b) => (a['horaInicio'] as int).compareTo(
                                b['horaInicio'] as int,
                              ),
                            );

                            if (turnosFuturos.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32.0),
                                child: Text(
                                  'No hay más turnos agendados para lo que queda del día.',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: turnosFuturos.length > 5
                                  ? 5
                                  : turnosFuturos.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 24,
                                color: Color(0xFFE2E8F0),
                              ),
                              itemBuilder: (context, index) {
                                final turno = turnosFuturos[index];
                                final int inicio = turno['horaInicio'] ?? 0;
                                final int duracion =
                                    turno['duracionHoras'] ?? 1;

                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    width: 70,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${inicio.toString().padLeft(2, '0')}:00',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    turno['nombreCliente'] ?? 'Cliente Externo',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${turno['cancha']} • Duración: $duracion hora(s)',
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  trailing: Chip(
                                    label: Text(
                                      turno['metodoPago'] == 'Cuenta Corriente'
                                          ? '📋 Cta Cte'
                                          : '💵 Caja',
                                      style: TextStyle(
                                        color:
                                            turno['metodoPago'] ==
                                                'Cuenta Corriente'
                                            ? Colors.indigo.shade900
                                            : Colors.teal.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    backgroundColor:
                                        turno['metodoPago'] ==
                                            'Cuenta Corriente'
                                        ? Colors.indigo.shade50
                                        : Colors.teal.shade50,
                                    side: BorderSide(
                                      color:
                                          turno['metodoPago'] ==
                                              'Cuenta Corriente'
                                          ? Colors.indigo.shade100
                                          : Colors.teal.shade100,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),

                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amber.shade800,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Alertas de Stock Crítico',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            StreamBuilder<QuerySnapshot>(
                              stream: _firestore
                                  .collection('inventario_general')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                    child: LinearProgressIndicator(),
                                  );
                                }

                                final criticos = snapshot.data!.docs.where((
                                  doc,
                                ) {
                                  final d = doc.data() as Map<String, dynamic>;
                                  final bool esCombo = d['esCombo'] ?? false;
                                  final int stock = (d['stockActual'] ?? 0)
                                      .toInt();
                                  final int minimo = (d['stockMinimo'] ?? 3)
                                      .toInt();
                                  return !esCombo && stock <= minimo;
                                }).toList();

                                if (criticos.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.green,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Inventario global al día',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: criticos.length > 3
                                      ? 3
                                      : criticos.length,
                                  itemBuilder: (context, idx) {
                                    final d =
                                        criticos[idx].data()
                                            as Map<String, dynamic>;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              d['nombre'] ?? 'Artículo',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red.shade900,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            'Quedan: ${d['stockActual']}',
                                            style: TextStyle(
                                              color: Colors.red.shade700,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Accesos de Caja Rápidos',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyanAccent,
                                foregroundColor: const Color(0xFF0F172A),
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => setState(
                                () => _pantallaActual = const PosCajaPage(),
                              ),
                              icon: const Icon(
                                Icons.point_of_sale_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Abrir Punto de Venta (Caja)',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(48),
                                side: const BorderSide(color: Colors.blueGrey),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => setState(
                                () => _pantallaActual = const CanchasPage(),
                              ),
                              icon: const Icon(
                                Icons.calendar_today_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Grilla de Canchas',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirVistaTorneos() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Torneos de Pádel',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              if (widget.rolUsuario == 'admin')
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0A3B43),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        side: const BorderSide(color: Color(0xFF0A3B43)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Sincronizando categorías con Padel Manager...',
                            ),
                          ),
                        );

                        final res = await AuthService()
                            .forzarSincronizacionRanking();

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res['mensaje']),
                              backgroundColor: res['exito']
                                  ? const Color(0xFF0A3B43)
                                  : Colors.redAccent,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text(
                        'Sincronizar Ranking',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A3B43),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CrearTorneoPage(),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Crear Nuevo Torneo',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('torneos').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay torneos registrados actualmente.',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final tData = docs[index].data() as Map<String, dynamic>;
                    final String tId = docs[index].id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 1.5,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: const Icon(
                          Icons.emoji_events,
                          color: Colors.amber,
                          size: 36,
                        ),
                        title: Text(
                          tData['nombre'] ?? 'Torneo de Pádel',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          'Categoría: ${tData['categoria']} | Rama: ${tData['rama']} | Estado: ${tData['estado']}',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey,
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetalleTorneoPage(
                              torneoId: tId,
                              esAdmin: widget.rolUsuario == 'admin',
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarSociosPage() {
    setState(() {
      _pantallaActual = SociosPage(
        rolUsuario: widget.rolUsuario,
        onNuevoSocio: () => setState(
          () => _pantallaActual = AltaSocioPage(onVolver: _mostrarSociosPage),
        ),
        onVerSocio: (socio) => setState(
          () => _pantallaActual = SocioDetallePage(
            socio: socio,
            onVolver: _mostrarSociosPage,
          ),
        ),
        onEditarSocio: (socio) => setState(
          () => _pantallaActual = EditarSocioPage(
            socio: socio,
            onVolver: _mostrarSociosPage,
          ),
        ),
      );
    });
  }

  bool _coincideFiltro(String titulo) {
    if (_filtroMenu.isEmpty) return true;
    return titulo.toLowerCase().contains(_filtroMenu.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rolUsuario != 'admin') {
      return StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('socios')
            .where('usuarioUid', isEqualTo: _userActual?.uid ?? '')
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final docSocio = snapshot.data!.docs.first;
            return SocioDashboardPage(
              socioId: docSocio.id,
              socioData: docSocio.data() as Map<String, dynamic>,
            );
          }

          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
              title: const Text('Portal de Socios'),
              backgroundColor: const Color(0xFF0A3B43),
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 70,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ficha pendiente de vinculación',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tu cuenta (${_userActual?.email}) aún no está vinculada a tu número de socio.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A3B43),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Volver al Login',
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: () async {
                        await AuthService().cerrarSesion();
                        if (context.mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool esMovil = constraints.maxWidth < _anchoBreakpointMovil;

        if (esMovil) {
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              title: const Text('OQUA CLUB'),
            ),
            drawer: Drawer(
              backgroundColor: AppColors.navy,
              child: SafeArea(child: _buildNavColumn()),
            ),
            body: _pantallaActual,
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          body: Row(
            children: [
              Container(
                width: 264,
                color: AppColors.navy,
                child: _buildNavColumn(),
              ),
              Expanded(child: _pantallaActual),
            ],
          ),
        );
      },
    );
  }

  // 🧭 Contenido del panel lateral (marca, buscador, menú, cerrar sesión) —
  // se reutiliza tanto en el Container fijo de escritorio como dentro del
  // Drawer en celular, para no mantener dos copias del menú.
  Widget _buildNavColumn() {
    return Column(
              children: [
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppColors.teal.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(
                          Icons.pool_rounded,
                          color: AppColors.tealLight,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'OQUA CLUB',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                letterSpacing: 0.2,
                              ),
                            ),
                            Text(
                              widget.rolUsuario.toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.tealLight,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFF1E293B), height: 1),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Filtrar menú...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF64748B),
                        size: 18,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setState(() => _filtroMenu = val),
                  ),
                ),
                const SizedBox(height: 6),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_coincideFiltro('Inicio'))
                          _buildMenuItem(
                            Icons.dashboard_rounded,
                            'Inicio',
                            onTap: () => setState(
                              () => _pantallaActual = _construirPanelInicio(),
                            ),
                          ),
                        _buildMenuSectionLabel('Socios & Acceso'),
                        if (_coincideFiltro('Control Acceso'))
                          _buildMenuItem(
                            Icons.fingerprint_rounded,
                            'Control Acceso (Socios)',
                            onTap: () => setState(
                              () => _pantallaActual = ControlAccesoPage(
                                rolUsuario: widget.rolUsuario,
                              ),
                            ),
                          ),
                        if (_coincideFiltro('Socios'))
                          _buildMenuItem(
                            Icons.people_alt_rounded,
                            'Socios',
                            onTap: _mostrarSociosPage,
                          ),
                        if (_coincideFiltro('Mensajería & Avisos'))
                          _buildMenuItem(
                            Icons.mark_email_unread_rounded,
                            'Mensajería & Avisos',
                            onTap: () => setState(
                              () => _pantallaActual = MensajeriaPage(
                                rolUsuario: widget.rolUsuario,
                              ),
                            ),
                          ),
                        _buildMenuSectionLabel('Gimnasio'),
                        if (_coincideFiltro('Clases de Gimnasio'))
                          _buildMenuItem(
                            Icons.fitness_center_rounded,
                            'Clases de Gimnasio',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const GestionClasesGimnasioPage(),
                            ),
                          ),
                        if (_coincideFiltro('Asignar Rutina'))
                          _buildMenuItem(
                            Icons.assignment_rounded,
                            'Asignar Rutina',
                            onTap: () => setState(
                              () => _pantallaActual = const AsignarRutinaPage(),
                            ),
                          ),
                        _buildMenuSectionLabel('Natatorio'),
                        if (_coincideFiltro('Andariveles'))
                          _buildMenuItem(
                            Icons.pool_rounded,
                            'Andariveles',
                            onTap: () => setState(
                              () => _pantallaActual = const AndarivelesPage(),
                            ),
                          ),
                        _buildMenuSectionLabel('Pádel'),
                        if (_coincideFiltro('Canchas & Turnos'))
                          _buildMenuItem(
                            Icons.sports_tennis_rounded,
                            'Canchas & Turnos',
                            onTap: () => setState(
                              () => _pantallaActual = const CanchasPage(),
                            ),
                          ),
                        if (_coincideFiltro('Canchas & Tarifas'))
                          _buildMenuItem(
                            Icons.tune_rounded,
                            'Canchas & Tarifas',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const ConfiguracionPaddlePage(),
                            ),
                          ),
                        if (_coincideFiltro('Explorador Reservas') ||
                            _coincideFiltro('Comprobantes'))
                          _buildMenuItem(
                            Icons.travel_explore_rounded,
                            'Explorador Reservas',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const ExploradorReservasPage(),
                            ),
                          ),
                        if (_coincideFiltro('Torneos de Pádel'))
                          _buildMenuItem(
                            Icons.emoji_events_rounded,
                            'Torneos de Pádel',
                            onTap: () => setState(
                              () => _pantallaActual = _construirVistaTorneos(),
                            ),
                          ),
                        if (_coincideFiltro('Partidos Abiertos'))
                          _buildMenuItem(
                            Icons.groups_rounded,
                            'Partidos Abiertos',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const AdminPartidosAbiertosPage(),
                            ),
                          ),
                        if (_coincideFiltro('Clases de Pádel'))
                          _buildMenuItem(
                            Icons.school_rounded,
                            'Clases de Pádel',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const GestionClasesPadelPage(),
                            ),
                          ),
                        if (_coincideFiltro('Turnos Fijos'))
                          _buildMenuItem(
                            Icons.event_repeat_rounded,
                            'Turnos Fijos',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const TurnosFijosPadelPage(),
                            ),
                          ),
                        if (_coincideFiltro('Reportes BI Pádel'))
                          _buildMenuItem(
                            Icons.bar_chart_rounded,
                            'Reportes BI Pádel',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const ReportesBiPadelPage(),
                            ),
                          ),
                        if (_coincideFiltro('Pro-Shop (Stock)'))
                          _buildMenuItem(
                            Icons.inventory_2_rounded,
                            'Pro-Shop (Stock)',
                            onTap: () => setState(
                              () => _pantallaActual = const InventarioGeneralPage(
                                filtroInicial: tipoInventarioProShop,
                              ),
                            ),
                          ),
                        if (_coincideFiltro('WhatsApp Pádel'))
                          _buildMenuItem(
                            Icons.chat_rounded,
                            'WhatsApp Pádel',
                            onTap: () => setState(
                              () => _pantallaActual = const ConfiguracionFiscalPage(
                                pestanaInicial: 2,
                              ),
                            ),
                          ),
                        _buildMenuSectionLabel('Buffet & Ventas'),
                        if (_coincideFiltro('Inventario Central'))
                          _buildMenuItem(
                            Icons.inventory_2_rounded,
                            'Inventario Central',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const InventarioGeneralPage(),
                            ),
                          ),
                        if (_coincideFiltro('Punto de Venta'))
                          _buildMenuItem(
                            Icons.point_of_sale_rounded,
                            'Punto de Venta (Caja)',
                            onTap: () => setState(
                              () => _pantallaActual = const PosCajaPage(),
                            ),
                          ),
                        if (_coincideFiltro('Explorador Ventas POS'))
                          _buildMenuItem(
                            Icons.analytics_outlined,
                            'Explorador Ventas POS',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const ExploradorVentasPage(),
                            ),
                          ),
                        if (_coincideFiltro('Menú del Buffet'))
                          _buildMenuItem(
                            Icons.restaurant_menu_rounded,
                            'Menú del Buffet',
                            onTap: () => setState(
                              () => _pantallaActual = const MenuBuffetPage(),
                            ),
                          ),
                        if (_coincideFiltro('Monitor de Cocina'))
                          _buildMenuItem(
                            Icons.soup_kitchen_rounded,
                            'Monitor de Cocina',
                            onTap: () => setState(
                              () => _pantallaActual = const MonitorCocinaPage(),
                            ),
                          ),
                        if (_coincideFiltro('Movimientos de Stock'))
                          _buildMenuItem(
                            Icons.swap_vert_rounded,
                            'Movimientos de Stock',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const ExploradorMovimientosStockPage(),
                            ),
                          ),
                        _buildMenuSectionLabel('Profesores'),
                        if (_coincideFiltro('Staff Profesores'))
                          _buildMenuItem(
                            Icons.badge_rounded,
                            'Staff Profesores',
                            onTap: () => setState(
                              () => _pantallaActual = ProfesoresPage(
                                esAdmin: widget.rolUsuario == 'admin',
                              ),
                            ),
                          ),
                        if (_coincideFiltro('Asistencia Profesores'))
                          _buildMenuItem(
                            Icons.fact_check_rounded,
                            'Asistencia Profesores',
                            onTap: () => setState(
                              () => _pantallaActual = const NominaDiariaPage(),
                            ),
                          ),
                        if (_coincideFiltro('Explorador Asistencias'))
                          _buildMenuItem(
                            Icons.history_rounded,
                            'Explorador Asistencias',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const ExploradorAsistenciasPage(),
                            ),
                          ),
                        if (_coincideFiltro('Asignar Cronogramas'))
                          _buildMenuItem(
                            Icons.edit_calendar_rounded,
                            'Asignar Cronogramas',
                            onTap: () => setState(
                              () => _pantallaActual = const CronogramasPage(),
                            ),
                          ),

                        if (widget.rolUsuario == 'admin') ...[
                          _buildMenuSectionLabel('Administración'),
                          if (_coincideFiltro('Sitio Web'))
                            _buildMenuItem(
                              Icons.language_rounded,
                              'Sitio Web',
                              onTap: () => setState(
                                () => _pantallaActual = const SitioWebPage(),
                              ),
                            ),
                          if (_coincideFiltro('Compras & Proveedores'))
                            _buildMenuItem(
                              Icons.local_shipping_rounded,
                              'Compras & Proveedores',
                              onTap: () => setState(
                                () => _pantallaActual =
                                    const ProveedoresComprasPage(),
                              ),
                            ),
                          if (_coincideFiltro('Liquidación Profesores') ||
                              _coincideFiltro('Liquidacion Profesores') ||
                              _coincideFiltro('Honorarios'))
                            _buildMenuItem(
                              Icons.calculate_rounded,
                              'Liquidación Profesores',
                              onTap: () => setState(
                                () => _pantallaActual =
                                    const LiquidacionesProfesoresPage(),
                              ),
                            ),
                          if (_coincideFiltro('Tesorería'))
                            _buildMenuItem(
                              Icons.monetization_on_rounded,
                              'Tesorería',
                              onTap: () => setState(
                                () => _pantallaActual = TesoreriaPage(
                                  rolUsuario: widget.rolUsuario,
                                ),
                              ),
                            ),
                          if (_coincideFiltro('Liquidación de Cuotas'))
                            _buildMenuItem(
                              Icons.receipt_long_rounded,
                              'Liquidación de Cuotas',
                              onTap: () => setState(
                                () => _pantallaActual =
                                    const LiquidacionCuotasPage(),
                              ),
                            ),
                          if (_coincideFiltro('Libros IVA & Fiscal'))
                            _buildMenuItem(
                              Icons.receipt_long_rounded,
                              'Libros IVA & Fiscal',
                              onTap: () => setState(
                                () => _pantallaActual =
                                    const TesoreriaLibrosIvaPage(),
                              ),
                            ),
                          if (_coincideFiltro('Reportes Generales'))
                            _buildMenuItem(
                              Icons.bar_chart_rounded,
                              'Reportes Generales (BI)',
                              onTap: () => setState(
                                () => _pantallaActual = const ReportesBiPage(),
                              ),
                            ),
                          if (_coincideFiltro('Configurar Tarifas'))
                            _buildMenuItem(
                              Icons.price_change_rounded,
                              'Configurar Tarifas',
                              onTap: () => setState(
                                () => _pantallaActual = const TarifasPage(),
                              ),
                            ),
                          if (_coincideFiltro('Usuarios'))
                            _buildMenuItem(
                              Icons.admin_panel_settings_rounded,
                              'Usuarios',
                              onTap: () => setState(
                                () => _pantallaActual = const UsuariosPage(),
                              ),
                            ),
                          if (_coincideFiltro('Auditoría'))
                            _buildMenuItem(
                              Icons.fact_check_outlined,
                              'Auditoría',
                              onTap: () => setState(
                                () => _pantallaActual = const AuditoriaPage(),
                              ),
                            ),
                          if (_coincideFiltro('Riesgo de Bajas') ||
                              _coincideFiltro('Churn'))
                            _buildMenuItem(
                              Icons.trending_down_rounded,
                              'Riesgo de Bajas',
                              onTap: () => setState(
                                () => _pantallaActual = const PanelRiesgoBajasPage(),
                              ),
                            ),
                          if (_coincideFiltro('Configuración') ||
                              _coincideFiltro('Ajustes') ||
                              _coincideFiltro('Paddle') ||
                              _coincideFiltro('Fiscales'))
                            Theme(
                              data: Theme.of(
                                context,
                              ).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                leading: const Icon(
                                  Icons.settings_suggest_rounded,
                                  color: Colors.blueGrey,
                                ),
                                title: const Text(
                                  'Configuración',
                                  style: TextStyle(
                                    color: Colors.blueGrey,
                                    fontSize: 14,
                                  ),
                                ),
                                iconColor: Colors.blueGrey,
                                collapsedIconColor: Colors.blueGrey,
                                childrenPadding: const EdgeInsets.only(
                                  left: 12.0,
                                ),
                                children: [
                                  _buildMenuItem(
                                    Icons.tune_rounded,
                                    'Ajustes del Sistema',
                                    onTap: () => setState(
                                      () => _pantallaActual =
                                          const ConfiguracionPage(),
                                    ),
                                  ),
                                  _buildMenuItem(
                                    Icons.sports_tennis_rounded,
                                    'Ajustes de Paddle',
                                    onTap: () => setState(
                                      () => _pantallaActual =
                                          const ConfiguracionPaddlePage(),
                                    ),
                                  ),
                                  _buildMenuItem(
                                    Icons.receipt_long_rounded,
                                    'Parámetros Fiscales & MP',
                                    onTap: () => setState(
                                      () => _pantallaActual =
                                          const ConfiguracionFiscalPage(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),

                const Divider(color: Color(0xFF1E293B), height: 1),
                ListTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: Colors.red.shade300,
                  ),
                  title: Text(
                    'Cerrar Sesión',
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  onTap: () async {
                    await AuthService().cerrarSesion();
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildMenuItem(
    IconData icon,
    String title, {
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          // 📱 En celular el menú vive dentro de un Drawer: además de
          // cambiar de pantalla, hay que cerrarlo (no-op si no hay Drawer
          // abierto, como en escritorio).
          onTap: () {
            onTap();
            _scaffoldKey.currentState?.closeDrawer();
          },
          hoverColor: Colors.white.withValues(alpha: 0.06),
          splashColor: AppColors.teal.withValues(alpha: 0.25),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF94A3B8), size: 19),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 📌 Encabezado de sección en el menú lateral (agrupa ítems relacionados
  // para que 25+ links no queden como una sola lista plana sin jerarquía).
  Widget _buildMenuSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // 🎨 Rediseño visual: antes cada card tenía su propio fondo pastel
  // (azul/verde/violeta/naranja) sin relación entre sí — un mosaico de
  // colores random en vez de una jerarquía visual. Ahora todas comparten la
  // misma superficie blanca + borde sutil de AppColors.line, y el color
  // "temático" queda sólo en el chip del ícono — más cohesivo, y consistente
  // con el resto del rediseño (POS, Control de Acceso).
  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color, [
    Color? backgroundColorIgnorado,
  ]) {
    return Expanded(
      child: MetricCard(label: title, value: value, icon: icon, accent: color),
    );
  }
}
