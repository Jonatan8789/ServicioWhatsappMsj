import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ExploradorReservasPage extends StatefulWidget {
  const ExploradorReservasPage({super.key});

  @override
  State<ExploradorReservasPage> createState() => _ExploradorReservasPageState();
}

class _ExploradorReservasPageState extends State<ExploradorReservasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _fechaFiltro = DateTime.now();
  String _estadoFiltro =
      'Todos'; // 'Todos', 'Pendiente', 'Comprobante Adjunto', 'Confirmada', 'Rechazada'
  String _canchaFiltro = 'Todas';

  final List<String> _opcionesEstado = [
    'Todos',
    'Pendiente',
    'Comprobante Adjunto',
    'Confirmada',
    'Rechazada',
  ];

  final List<String> _opcionesCanchas = [
    'Todas',
    'Cancha 1 Cristal',
    'Cancha 2 Cristal',
    'Cancha 3 Muro',
  ];

  Future<void> _cambiarEstadoReserva({
    required String reservaId,
    required String nuevoEstado,
    required Map<String, dynamic> reservaData,
  }) async {
    await _firestore.collection('reservas_canchas').doc(reservaId).update({
      'estadoReserva': nuevoEstado,
      'fechaUltimoCambioEstado': DateTime.now(),
    });

    // 🚨 El comentario original decía "si era con transferencia" pero el
    // código nunca chequeaba metodoPago: el botón "Aprobar/Confirmar" no
    // distingue el estado actual, así que aprobar CUALQUIER reserva (incluso
    // una ya paga por Cuenta Corriente/Efectivo/Mercado Pago, que ya se cobró
    // o se dejó en ventas_pendientes para caja) volvía a cobrarla acá.
    // Ahora sólo se registra el cobro automático cuando el método de pago
    // real de la reserva es 'Transferencia'.
    if (nuevoEstado == 'Confirmada' &&
        reservaData['socioId'] != null &&
        reservaData['metodoPago'] == 'Transferencia') {
      final double precio = (reservaData['precio'] as num?)?.toDouble() ?? 0.0;
      final batch = _firestore.batch();
      // 🚨 Antes se escribía 'monto' positivo y nunca se tocaba
      // saldoCuentaCorriente: el cargo quedaba invisible en el saldo
      // mostrado en el resto de la app, y en el propio ledger no se
      // renderizaba como deuda (esDeuda espera monto negativo, como en
      // pos_caja_page.dart).
      batch.set(
        _firestore
            .collection('socios')
            .doc(reservaData['socioId'])
            .collection('cuenta_corriente')
            .doc(),
        {
          'fecha': DateTime.now(),
          'tipo': 'Cobro Reserva Cancha (Transferencia Aprobada)',
          'monto': -precio,
          'detalle':
              'Reserva cancha ${reservaData['cancha']} (${reservaData['horaInicio']}hs) - Comprobante Aprobado',
        },
      );
      batch.update(
        _firestore.collection('socios').doc(reservaData['socioId']),
        {'saldoCuentaCorriente': FieldValue.increment(-precio)},
      );
      await batch.commit();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Reserva actualizada a "$nuevoEstado"'),
          backgroundColor: nuevoEstado == 'Confirmada'
              ? Colors.green
              : Colors.orange,
        ),
      );
    }
  }

  void _abrirComprobante(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Enlace del Comprobante'),
            content: SelectableText(url),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String fechaIdStr =
        "${_fechaFiltro.year}-${_fechaFiltro.month}-${_fechaFiltro.day}";

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Explorador de Reservas & Comprobantes'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // BARRA DE FILTROS SUPERIOR
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Filtro de Fecha
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        'Fecha: ${DateFormat('dd/MM/yyyy').format(_fechaFiltro)}',
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _fechaFiltro,
                          firstDate: DateTime(2023),
                          lastDate: DateTime.now().add(
                            const Duration(days: 60),
                          ),
                        );
                        if (picked != null)
                          setState(() => _fechaFiltro = picked);
                      },
                    ),
                    const SizedBox(width: 16),

                    // Filtro por Estado
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _estadoFiltro,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por Estado',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _opcionesEstado
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _estadoFiltro = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Filtro por Cancha
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _canchaFiltro,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por Cancha',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _opcionesCanchas
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _canchaFiltro = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // LISTADO EN TIEMPO REAL
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('reservas_canchas').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docsFiltrados = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final String rId = doc.id;
                    final String estado = data['estadoReserva'] ?? 'Confirmada';
                    final String cancha = data['cancha'] ?? '';

                    // 🚨 Sin el "_" de cierre, el día 1 (prefijo "2026-9-1")
                    // también matcheaba los IDs de los días 10 a 19
                    // ("2026-9-10_...", "2026-9-19_...").
                    bool coincideFecha = rId.startsWith('${fechaIdStr}_');
                    bool coincideEstado =
                        _estadoFiltro == 'Todos' || estado == _estadoFiltro;
                    bool coincideCancha =
                        _canchaFiltro == 'Todas' || cancha == _canchaFiltro;

                    return coincideFecha && coincideEstado && coincideCancha;
                  }).toList();

                  if (docsFiltrados.isEmpty) {
                    return const Center(
                      child: Text(
                        'No hay reservas que coincidan con los filtros elegidos.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: docsFiltrados.length,
                    itemBuilder: (context, idx) {
                      final doc = docsFiltrados[idx];
                      final data = doc.data() as Map<String, dynamic>;
                      final String reservaId = doc.id;
                      final String estado =
                          data['estadoReserva'] ?? 'Confirmada';
                      final String? comprobanteUrl = data['comprobanteUrl'];

                      Color colorEstado = Colors.green;
                      if (estado == 'Pendiente') colorEstado = Colors.orange;
                      if (estado == 'Comprobante Adjunto')
                        colorEstado = Colors.blue;
                      if (estado == 'Rechazada') colorEstado = Colors.red;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: colorEstado.withOpacity(0.4)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: colorEstado.withOpacity(0.1),
                            child: Icon(
                              Icons.sports_tennis,
                              color: colorEstado,
                            ),
                          ),
                          title: Text(
                            '${data['nombreCliente'] ?? 'Cliente'} — ${data['cancha'] ?? 'Cancha'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'Horario: ${data['horaInicio']}:00 hs • Monto: \$${data['precio']} ARS',
                              ),
                              Text(
                                'Medio de Pago: ${data['metodoPago'] ?? 'Transferencia'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (comprobanteUrl != null &&
                                  comprobanteUrl.isNotEmpty)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade800,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.attach_file, size: 16),
                                  label: const Text('Ver Comprobante'),
                                  onPressed: () =>
                                      _abrirComprobante(comprobanteUrl),
                                ),
                              const SizedBox(width: 8),

                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (nuevoEstado) =>
                                    _cambiarEstadoReserva(
                                      reservaId: reservaId,
                                      nuevoEstado: nuevoEstado,
                                      reservaData: data,
                                    ),
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'Confirmada',
                                    child: Text('✅ Aprobar / Confirmar'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'Comprobante Adjunto',
                                    child: Text('📑 En Revisión'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'Rechazada',
                                    child: Text('❌ Rechazar'),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
