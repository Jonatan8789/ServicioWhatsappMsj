import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CuentaCorrienteSocioPage extends StatefulWidget {
  final String socioId;
  final String nombreSocio;

  const CuentaCorrienteSocioPage({
    super.key,
    required this.socioId,
    required this.nombreSocio,
  });

  @override
  State<CuentaCorrienteSocioPage> createState() =>
      _CuentaCorrienteSocioPageState();
}

class _CuentaCorrienteSocioPageState extends State<CuentaCorrienteSocioPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _filtroTipo = 'Todos';
  String _filtroFecha = 'Todo';
  String _busquedaConcepto = '';
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  bool _evaluarFiltroFecha(DateTime fechaMov) {
    final ahora = DateTime.now();
    if (_filtroFecha == 'Hoy') {
      return fechaMov.year == ahora.year &&
          fechaMov.month == ahora.month &&
          fechaMov.day == ahora.day;
    } else if (_filtroFecha == '7dias') {
      return ahora.difference(fechaMov).inDays <= 7;
    } else if (_filtroFecha == '30dias') {
      return ahora.difference(fechaMov).inDays <= 30;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Cuenta Corriente: ${widget.nombreSocio}'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================
            // 🚨 ENCABEZADO: TOTALIZADOR DE SALDO EN TIEMPO REAL BLINDADO
            // ==========================================
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore
                  .collection('socios')
                  .doc(widget.socioId)
                  .snapshots(),
              builder: (context, socioSnapshot) {
                if (socioSnapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                if (socioSnapshot.hasError ||
                    !socioSnapshot.hasData ||
                    !socioSnapshot.data!.exists) {
                  return const SizedBox(height: 10);
                }

                final socioData =
                    socioSnapshot.data!.data() as Map<String, dynamic>? ?? {};

                // 🚨 LEE EL CAMPO EXACTO
                final double saldo = (socioData['saldoCuentaCorriente'] ?? 0.0)
                    .toDouble();

                // 🚨 AHORA NEGATIVO ES DEUDA, POSITIVO ES A FAVOR
                final bool tieneDeuda = saldo < 0;
                final bool saldoAFavor = saldo > 0;

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: tieneDeuda
                        ? const Color(0xFFFEF2F2)
                        : (saldoAFavor
                              ? Colors.blue.shade50
                              : const Color(0xFFF0FDF4)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: tieneDeuda
                          ? Colors.red.shade200
                          : (saldoAFavor
                                ? Colors.blue.shade200
                                : Colors.green.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ESTADO DE CUENTA ACTUAL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tieneDeuda
                                ? 'Socio con Saldo Deudor'
                                : (saldoAFavor
                                      ? 'Saldo a Favor'
                                      : 'Cuenta al Día / Sin Deuda'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: tieneDeuda
                                  ? Colors.red.shade900
                                  : (saldoAFavor
                                        ? Colors.blue.shade900
                                        : Colors.green.shade900),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        tieneDeuda
                            ? '\$${saldo.abs().toStringAsFixed(0)}'
                            : (saldoAFavor
                                  ? '+\$${saldo.abs().toStringAsFixed(0)}'
                                  : '\$0'),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: tieneDeuda
                              ? Colors.red.shade700
                              : (saldoAFavor
                                    ? Colors.blue.shade700
                                    : Colors.green.shade700),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            // ==========================================
            // BARRA DE FILTROS AVANZADA
            // ==========================================
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _busquedaController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por concepto (Ej: Cancha)...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          setState(() => _busquedaConcepto = v.toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _filtroTipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Movimiento',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Todos',
                          child: Text('Todos los movimientos'),
                        ),
                        DropdownMenuItem(
                          value: 'Cargo / Deuda',
                          child: Text('Solo Deudas ↗'),
                        ),
                        DropdownMenuItem(
                          value: 'Pago',
                          child: Text('Solo Pagos ↙'),
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _filtroTipo = val ?? 'Todos'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _filtroFecha,
                      decoration: const InputDecoration(
                        labelText: 'Período',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Todo',
                          child: Text('Todo el historial'),
                        ),
                        DropdownMenuItem(value: 'Hoy', child: Text('Solo Hoy')),
                        DropdownMenuItem(
                          value: '7dias',
                          child: Text('Últimos 7 días'),
                        ),
                        DropdownMenuItem(
                          value: '30dias',
                          child: Text('Últimos 30 días'),
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _filtroFecha = val ?? 'Todo'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ==========================================
            // LISTADO DE MOVIMIENTOS FILTRADO
            // ==========================================
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('socios')
                      .doc(widget.socioId)
                      .collection('movimientos')
                      .orderBy('fecha', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('Sin movimientos registrados.'),
                      );
                    }

                    final docsFiltrados = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final tipo = data['tipo']?.toString() ?? '';
                      final concepto =
                          data['concepto']?.toString().toLowerCase() ?? '';
                      final Timestamp? timestamp = data['fecha'] as Timestamp?;
                      final fechaMov = timestamp?.toDate() ?? DateTime.now();

                      if (_filtroTipo != 'Todos' &&
                          !tipo.contains(_filtroTipo)) {
                        return false;
                      }
                      if (_busquedaConcepto.isNotEmpty &&
                          !concepto.contains(_busquedaConcepto)) {
                        return false;
                      }
                      return _evaluarFiltroFecha(fechaMov);
                    }).toList();

                    if (docsFiltrados.isEmpty) {
                      return const Center(
                        child: Text(
                          'Ningún movimiento coincide con los filtros.',
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: docsFiltrados.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Color(0xFFF1F5F9)),
                      itemBuilder: (context, index) {
                        final data =
                            docsFiltrados[index].data() as Map<String, dynamic>;
                        final String tipo = data['tipo'] ?? 'Movimiento';
                        final double importe =
                            (data['importe'] as num?)?.toDouble() ?? 0.0;
                        final String concepto = data['concepto'] ?? '';
                        final Timestamp? t = data['fecha'] as Timestamp?;
                        final fecha = t?.toDate() ?? DateTime.now();

                        // Condición visual para pintar la deuda
                        final esDeuda = importe < 0 || tipo == 'Cargo / Deuda';

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: esDeuda
                                ? const Color(0xFFFEE2E2)
                                : const Color(0xFFDCFCE7),
                            child: Icon(
                              esDeuda
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: esDeuda ? Colors.red : Colors.green,
                            ),
                          ),
                          title: Text(
                            concepto,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          subtitle: Text(
                            '${fecha.day}/${fecha.month}/${fecha.year} • Tipo: $tipo',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            '${esDeuda ? "-" : "+"}\$${importe.abs().toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: esDeuda
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
