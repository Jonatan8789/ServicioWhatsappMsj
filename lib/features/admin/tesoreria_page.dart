import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class TesoreriaPage extends StatefulWidget {
  final String rolUsuario;
  const TesoreriaPage({super.key, required this.rolUsuario});

  @override
  State<TesoreriaPage> createState() => _TesoreriaPageState();
}

class _TesoreriaPageState extends State<TesoreriaPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _nombreNuevaTerminalCtrl = TextEditingController();
  bool _verPanelABM = false;
  String? _terminalSeleccionadaNombre;

  @override
  void dispose() {
    _nombreNuevaTerminalCtrl.dispose();
    super.dispose();
  }

  Widget _buildResumenFiscalDiario() {
    final DateTime hoy = DateTime.now();
    final DateTime inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('ventas_buffet')
          .where('fecha', isGreaterThanOrEqualTo: inicioHoy)
          .snapshots(),
      builder: (context, snapVentas) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('ordenes_de_pago')
              .where('fecha', isGreaterThanOrEqualTo: inicioHoy)
              .snapshots(),
          builder: (context, snapOP) {
            if (!snapVentas.hasData || !snapOP.hasData) {
              return const Center(child: LinearProgressIndicator());
            }

            double totalFiscalizado = 0.0;
            double totalPendiente = 0.0;
            double totalEgresosOP = 0.0;

            for (var doc in snapVentas.data!.docs) {
              final v = doc.data() as Map<String, dynamic>;
              final m = (v['total'] as num?)?.toDouble() ?? 0.0;
              if (v['fiscalizado'] == true) {
                totalFiscalizado += m;
              } else {
                totalPendiente += m;
              }
            }

            for (var doc in snapOP.data!.docs) {
              final op = doc.data() as Map<String, dynamic>;
              totalEgresosOP +=
                  (op['montoNetoPago'] as num?)?.toDouble() ?? 0.0;
            }

            final double balanceCajaNeto =
                (totalFiscalizado + totalPendiente) - totalEgresosOP;

            return Card(
              color: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.account_balance_rounded,
                          color: Colors.cyanAccent,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Balance Fiscal & Caja Diaria (Hoy)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMetricTile(
                          '🟢 Ventas ARCA (CAE)',
                          '\$${totalFiscalizado.toStringAsFixed(2)}',
                          Colors.greenAccent,
                        ),
                        _buildMetricTile(
                          '🔴 Ventas Sin CAE',
                          '\$${totalPendiente.toStringAsFixed(2)}',
                          Colors.orangeAccent,
                        ),
                        _buildMetricTile(
                          '💸 Egresos OP/Proveedores',
                          '\$${totalEgresosOP.toStringAsFixed(2)}',
                          Colors.redAccent,
                        ),
                        _buildMetricTile(
                          '💰 Balance Neto Caja',
                          '\$${balanceCajaNeto.toStringAsFixed(2)}',
                          Colors.cyanAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricTile(String label, String valor, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          valor,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ],
    );
  }

  // 🏪 AUDITORÍA DE VALORES DE LA TERMINAL SELECCIONADA
  Widget _buildDetalleTerminalSeleccionada(DocumentSnapshot? docCajaAbierta) {
    if (docCajaAbierta == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              '$_terminalSeleccionadaNombre se encuentra actualmente CERRADA.\nNo hay una sesión activa con movimientos en tiempo real.',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      );
    }

    final data = docCajaAbierta.data() as Map<String, dynamic>;
    final double tArs =
        (data['montoInicialARS'] as num?)?.toDouble() ??
        (data['totalEfectivoARS'] as num?)?.toDouble() ??
        0.0;
    final double tUsd = (data['totalEfectivoUSD'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.2,
          children: [
            _cardMonto(
              'Fondo + Efectivo Pesos',
              '\$${tArs.toStringAsFixed(2)} ARS',
              Colors.teal,
            ),
            _cardMonto(
              'Fondo + Efectivo Dólares',
              'US\$ ${tUsd.toStringAsFixed(2)}',
              Colors.amber,
            ),
            _cardMonto(
              'Recaudado Mercado Pago',
              '\$${((data['totalMercadoPago'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ARS',
              Colors.blue,
            ),
            _cardMonto(
              'Recaudado MODO',
              '\$${((data['totalModo'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ARS',
              Colors.purple,
            ),
            _cardMonto(
              'Débito Posnet',
              '\$${((data['totalTarjetaDebito'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ARS',
              Colors.indigo,
            ),
            _cardMonto(
              'Crédito Posnet',
              '\$${((data['totalTarjetaCredito'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ARS',
              Colors.orange,
            ),
            _cardMonto(
              'Transferencias CBU',
              '\$${((data['totalTransferencia'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ARS',
              Colors.cyan,
            ),
            _cardMonto(
              'Fiar / Cuenta Corriente',
              '\$${((data['totalCtaCte'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ARS',
              Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 30),
        const Text(
          'Auditoría de Novedades e Incidencias en Vivo:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildListaMovimientosCaja(docCajaAbierta.id),
      ],
    );
  }

  Widget _buildListaMovimientosCaja(String cajaId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('auditoria_movimientos_caja')
          .where('cajaId', isEqualTo: cajaId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Text(
            'Sin movimientos extraordinarios asentados en este turno.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final m = docs[i].data() as Map<String, dynamic>;
            final bool esEgreso =
                m['tipo'].toString().contains('Egreso') ||
                m['tipo'].toString().contains('Faltante');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  esEgreso ? Icons.arrow_downward : Icons.arrow_upward,
                  color: esEgreso ? Colors.red : Colors.green,
                ),
                title: Text(
                  '${m['tipo']} - \$${(m['monto'] as num).toStringAsFixed(2)} ARS',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Concepto: ${m['justificacion']} • Por: ${m['ejecuto']}',
                ),
                trailing: Text(
                  DateFormat(
                    'HH:mm',
                  ).format((m['fecha'] as Timestamp).toDate()),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistorialGlobalCerradas(List<DocumentSnapshot> allDocs) {
    final List<DocumentSnapshot> cerradas = [];
    for (var d in allDocs) {
      if ((d.data() as Map<String, dynamic>)['estado'] == 'Cerrada') {
        cerradas.add(d);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Historial de Cajas Cerradas y Arqueos Consolidados',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        if (cerradas.isEmpty)
          const Text(
            'No hay registros de cierres en el sistema.',
            style: TextStyle(color: Colors.grey),
          ),
        if (cerradas.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cerradas.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, idx) {
                final data = cerradas[idx].data() as Map<String, dynamic>;
                final inicio = (data['fechaApertura'] as Timestamp).toDate();
                final fin = data['fechaCierre'] != null
                    ? (data['fechaCierre'] as Timestamp).toDate()
                    : DateTime.now();

                return ListTile(
                  leading: const Icon(
                    Icons.history_toggle_off_rounded,
                    color: Colors.blueGrey,
                  ),
                  title: Text(
                    'Caja: [${data['nombreCajaTerminal'] ?? "General"}] • Turno: ${data['usuario']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Apertura: ${DateFormat('dd/MM/yyyy HH:mm').format(inicio)} | Cierre: ${DateFormat('HH:mm').format(fin)}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${((data['totalFinalGeneral'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)} ARS',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                          fontSize: 16,
                        ),
                      ),
                      const Text(
                        'Total Consolidado',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSeccionABMTerminales() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Maestro de Puntos de Venta Físicos (ABM Cajas)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nombreNuevaTerminalCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la Caja (Ej: Caja Recepción Pádel)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(180, 54),
                ),
                onPressed: () async {
                  final nom = _nombreNuevaTerminalCtrl.text.trim();
                  if (nom.isEmpty) return;
                  await _firestore.collection('terminales_caja').add({
                    'nombre': nom,
                    'activa': true,
                    'fechaCreacion': DateTime.now(),
                  });
                  _nombreNuevaTerminalCtrl.clear();
                },
                child: const Text(
                  'Guardar Terminal',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Terminales Registradas:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('terminales_caja').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final docs = snapshot.data!.docs;

              if (docs.isEmpty)
                return const Text(
                  'No hay terminales registradas.',
                  style: TextStyle(color: Colors.grey),
                );

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.point_of_sale,
                      color: Colors.blue,
                    ),
                    title: Text(data['nombre'] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _firestore
                          .collection('terminales_caja')
                          .doc(docs[i].id)
                          .delete(),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cardMonto(String title, String val, Color c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: c,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            val,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool esAdmin = widget.rolUsuario == 'admin';

    if (!esAdmin) {
      return const Scaffold(
        body: Center(
          child: Text(
            '⚠️ Acceso Restringido. Esta consola es de uso exclusivo para la Administración Central.',
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('terminales_caja').snapshots(),
        builder: (context, snapTerminales) {
          return StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('control_cajas').snapshots(),
            builder: (context, snapSesiones) {
              if (!snapTerminales.hasData || !snapSesiones.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.indigo),
                );
              }

              final terminalesDocs = snapTerminales.data!.docs;
              final sesionesDocs = snapSesiones.data!.docs;

              // Obtiene los nombres únicos de todas las cajas creadas
              List<String> nombresTerminales = terminalesDocs
                  .map(
                    (doc) =>
                        (doc.data() as Map<String, dynamic>)['nombre']
                            as String? ??
                        '',
                  )
                  .where((n) => n.isNotEmpty)
                  .toList();

              if (nombresTerminales.isEmpty) {
                nombresTerminales = ['Caja Recepcion', 'Caja Padel'];
              }

              if (_terminalSeleccionadaNombre == null ||
                  !nombresTerminales.contains(_terminalSeleccionadaNombre)) {
                _terminalSeleccionadaNombre = nombresTerminales.first;
              }

              // Mapea qué cajas están abiertas actualmente en control_cajas
              Map<String, DocumentSnapshot> cajasAbiertasMap = {};
              for (var doc in sesionesDocs) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['estado'] == 'Abierta') {
                  final String nombreTerm =
                      data['nombreCajaTerminal'] ?? 'General';
                  cajasAbiertasMap[nombreTerm] = doc;
                }
              }

              DocumentSnapshot? docSesionActiva =
                  cajasAbiertasMap[_terminalSeleccionadaNombre];

              return SingleChildScrollView(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Consola de Tesorería y Auditoría Global',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Monitoreo en tiempo real de terminales, medios de pago y desgloses financieros.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () =>
                              setState(() => _verPanelABM = !_verPanelABM),
                          icon: const Icon(Icons.settings),
                          label: Text(
                            _verPanelABM
                                ? 'Ocultar ABM'
                                : 'Configurar Maestro Cajas',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildResumenFiscalDiario(),
                    if (_verPanelABM) ...[
                      const SizedBox(height: 20),
                      _buildSeccionABMTerminales(),
                    ],
                    const SizedBox(height: 30),

                    // 🏢 SELECTOR DE TERMINALES DEL ABM CON ESTADO OPERATIVO
                    const Text(
                      'Seleccionar Terminal Física para Inspección de Medios de Pago:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _terminalSeleccionadaNombre,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      ),
                      items: nombresTerminales.map((nombre) {
                        final estaAbierta = cajasAbiertasMap.containsKey(
                          nombre,
                        );
                        String textoDetalle = '$nombre - Estado: CERRADA';

                        if (estaAbierta) {
                          final dataSesion =
                              cajasAbiertasMap[nombre]!.data()
                                  as Map<String, dynamic>;
                          final op = dataSesion['usuario'] ?? 'Operador';
                          textoDetalle =
                              '🟢 $nombre - ABIERTA (Responsable: $op)';
                        }

                        return DropdownMenuItem<String>(
                          value: nombre,
                          child: Text(textoDetalle),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setState(() => _terminalSeleccionadaNombre = v),
                    ),
                    const SizedBox(height: 24),
                    _buildDetalleTerminalSeleccionada(docSesionActiva),

                    const SizedBox(height: 40),
                    _buildHistorialGlobalCerradas(sesionesDocs),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
