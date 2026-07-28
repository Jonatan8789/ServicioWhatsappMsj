import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:natatorio_app/features/admin/proveedores_compras_page.dart';
import 'package:natatorio_app/features/admin/reportes_bi_page.dart';
import 'package:natatorio_app/features/buffet/explorador_ventas_page.dart';
import 'package:natatorio_app/features/inventario/inventario_general_page.dart';
import 'package:natatorio_app/features/paddle/canchas_page.dart';
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
import '../buffet/pos_caja_page.dart';
import '../buffet/monitor_cocina_page.dart';
import '../buffet/menu_buffet_page.dart';

class DashboardPage extends StatefulWidget {
  final String rolUsuario;

  const DashboardPage({super.key, required this.rolUsuario});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Widget _pantallaActual;

  @override
  void initState() {
    super.initState();
    _pantallaActual = _construirPanelInicio();
  }

  Widget _construirPanelInicio() {
    final DateTime ahora = DateTime.now();
    final String fechaIdStr = "${ahora.year}-${ahora.month}-${ahora.day}";
    final int horaActual = ahora.hour;

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¡Bienvenido de nuevo, ${widget.rolUsuario == 'admin' ? 'Administrador' : 'Usuario'}!',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              'Estado operativo del club para hoy (${ahora.day}/${ahora.month}/${ahora.year}).',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),

            Row(
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('socios').snapshots(),
                  builder: (context, snapshot) {
                    final String total = snapshot.hasData
                        ? snapshot.data!.docs.length.toString()
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
                const SizedBox(width: 20),

                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('reservas_canchas').snapshots(),
                  builder: (context, snapshot) {
                    String porcentaje = '0%';
                    if (snapshot.hasData) {
                      final deHoy = snapshot.data!.docs
                          .where((doc) => doc.id.startsWith(fechaIdStr))
                          .length;
                      if (deHoy > 0) {
                        double calculo = (deHoy / 45) * 100;
                        porcentaje = "${calculo.toStringAsFixed(0)}%";
                      }
                    }
                    return _buildMetricCard(
                      'Ocupación Canchas Hoy',
                      porcentaje,
                      Icons.analytics_rounded,
                      Colors.orange.shade700,
                      const Color(0xFFFFF7ED),
                    );
                  },
                ),

                if (widget.rolUsuario == 'admin') ...[
                  const SizedBox(width: 20),
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('ventas_buffet').snapshots(),
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
                        'Caja Buffet (Total)',
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
                          stream: _firestore
                              .collection('reservas_canchas')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: LinearProgressIndicator(),
                              );
                            }

                            final turnosFuturos = snapshot.data!.docs
                                .map((doc) {
                                  return doc.data() as Map<String, dynamic>;
                                })
                                .where((r) {
                                  final String rId = r['id'] ?? '';
                                  final int rInicio = r['horaInicio'] ?? 0;
                                  return rId.startsWith(fechaIdStr) &&
                                      rInicio >= horaActual;
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
                                'Abrir Punto de Venta (POS)',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        children: [
          Container(
            width: 260,
            color: const Color(0xFF1E293B),
            child: Column(
              children: [
                const SizedBox(height: 40),
                ListTile(
                  leading: const Icon(
                    Icons.pool,
                    color: Colors.cyanAccent,
                    size: 32,
                  ),
                  title: const Text(
                    'OQUA CLUB DEPORTIVO',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    'Rol: ${widget.rolUsuario.toUpperCase()}',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(color: Colors.blueAccent),
                const SizedBox(height: 10),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildMenuItem(
                          Icons.dashboard_rounded,
                          'Inicio',
                          onTap: () => setState(
                            () => _pantallaActual = _construirPanelInicio(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.fingerprint_rounded,
                          'Control Acceso (Socios)',
                          onTap: () => setState(
                            () => _pantallaActual = ControlAccesoPage(
                              rolUsuario: widget.rolUsuario,
                            ),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.people_alt_rounded,
                          'Socios',
                          onTap: _mostrarSociosPage,
                        ),
                        _buildMenuItem(
                          Icons.mark_email_unread_rounded,
                          'Mensajería & Avisos',
                          onTap: () => setState(
                            () => _pantallaActual = MensajeriaPage(
                              rolUsuario: widget.rolUsuario,
                            ),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.sports_tennis_rounded,
                          'Canchas & Turnos',
                          onTap: () => setState(
                            () => _pantallaActual = const CanchasPage(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.inventory_2_rounded,
                          'Inventario Central',
                          onTap: () => setState(
                            () =>
                                _pantallaActual = const InventarioGeneralPage(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.point_of_sale_rounded,
                          'Punto de Venta',
                          onTap: () => setState(
                            () => _pantallaActual = const PosCajaPage(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.analytics_outlined,
                          'Explorador Ventas POS',
                          onTap: () => setState(
                            () =>
                                _pantallaActual = const ExploradorVentasPage(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.restaurant_menu_rounded,
                          'Menú del Buffet',
                          onTap: () => setState(
                            () => _pantallaActual = const MenuBuffetPage(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.local_shipping_rounded,
                          'Compras & Proveedores',
                          onTap: () => setState(
                            () => _pantallaActual =
                                const ProveedoresComprasPage(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.soup_kitchen_rounded,
                          'Monitor de Cocina',
                          onTap: () => setState(
                            () => _pantallaActual = const MonitorCocinaPage(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.badge_rounded,
                          'Staff Profesores',
                          onTap: () => setState(
                            () => _pantallaActual = ProfesoresPage(
                              esAdmin: widget.rolUsuario == 'admin',
                            ),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.fact_check_rounded,
                          'Asistencia Profesores',
                          onTap: () => setState(
                            () => _pantallaActual = const NominaDiariaPage(),
                          ),
                        ),
                        _buildMenuItem(
                          Icons.edit_calendar_rounded,
                          'Asignar Cronogramas',
                          onTap: () => setState(
                            () => _pantallaActual = const CronogramasPage(),
                          ),
                        ),

                        if (widget.rolUsuario == 'admin') ...[
                          _buildMenuItem(
                            Icons.monetization_on_rounded,
                            'Tesorería',
                            onTap: () => setState(
                              () => _pantallaActual = TesoreriaPage(
                                rolUsuario: widget.rolUsuario,
                              ),
                            ),
                          ),
                          _buildMenuItem(
                            Icons.receipt_long_rounded,
                            'Liquidación de Cuotas',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const LiquidacionCuotasPage(),
                            ),
                          ),
                          _buildMenuItem(
                            Icons.receipt_long_rounded,
                            'Libros IVA & Fiscal',
                            onTap: () => setState(
                              () => _pantallaActual =
                                  const TesoreriaLibrosIvaPage(),
                            ),
                          ),
                          _buildMenuItem(
                            Icons.bar_chart_rounded,
                            'Reportes Generales (BI)',
                            onTap: () => setState(
                              () => _pantallaActual = const ReportesBiPage(),
                            ),
                          ),
                          _buildMenuItem(
                            Icons.price_change_rounded,
                            'Configurar Tarifas',
                            onTap: () => setState(
                              () => _pantallaActual = const TarifasPage(),
                            ),
                          ),
                          _buildMenuItem(
                            Icons.admin_panel_settings_rounded,
                            'Usuarios',
                            onTap: () => setState(
                              () => _pantallaActual = const UsuariosPage(),
                            ),
                          ),
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

                const Divider(color: Colors.blueAccent),
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Cerrar Sesión',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () async {
                    await AuthService().cerrarSesion();
                    if (context.mounted) {
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
            ),
          ),

          Expanded(child: _pantallaActual),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    IconData icon,
    String title, {
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: Colors.blueGrey),
        title: Text(
          title,
          style: const TextStyle(color: Colors.blueGrey, fontSize: 14),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color backgroundColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, size: 28, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
