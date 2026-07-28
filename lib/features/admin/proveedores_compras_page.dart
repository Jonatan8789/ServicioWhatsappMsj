import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'nueva_factura_compra_dialog.dart';
import 'orden_pago_dialog.dart';
import 'proveedores_explorador_padron_dialog.dart';
import 'libro_iva_compras_page.dart';

class ProveedoresComprasPage extends StatefulWidget {
  const ProveedoresComprasPage({super.key});

  @override
  State<ProveedoresComprasPage> createState() => _ProveedoresComprasPageState();
}

class _ProveedoresComprasPageState extends State<ProveedoresComprasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Filtros de Búsqueda
  String _filtroTipoComprobante = 'TODOS';
  String _filtroEstadoPago = 'TODOS';
  String _busquedaProveedor = '';
  DateTimeRange? _filtroFechas;

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
          'Gestión de Compras & Proveedores',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 📊 1. BOTÓN LIBRO IVA COMPRAS
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.tealAccent,
              side: const BorderSide(color: Colors.tealAccent, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _abrirLibroIvaCompras(context),
            icon: const Icon(Icons.analytics_rounded, size: 18),
            label: const Text(
              'Libro IVA',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),

          // 👥 2. BOTÓN PADRÓN PROVEEDORES
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _abrirPadronProveedores(context),
            icon: const Icon(Icons.people_alt_rounded, size: 18),
            label: const Text(
              'Padrón',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),

          // 📄 3. BOTÓN INGRESAR FACTURA
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _abrirDialogoNuevaFactura(context),
            icon: const Icon(Icons.note_add_rounded, size: 18),
            label: const Text(
              'Ingresar Factura',
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
            // 🔍 BARRA DE FILTROS Y BÚSQUEDA
            _construirBarraFiltros(),
            const SizedBox(height: 20),

            // 📋 TABLA / EXPLORADOR DE FACTURAS DE COMPRA
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('compras_facturas')
                        .orderBy('fechaEmision', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error al cargar comprobantes: ${snapshot.error}',
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      var docs = snapshot.data!.docs;

                      // Aplicación de Filtros Local
                      var facturas = docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final String tipo = data['tipoComprobante'] ?? '';
                        final String estado = data['estadoPago'] ?? 'PENDIENTE';
                        final String prov = (data['razonSocialProveedor'] ?? '')
                            .toString()
                            .toLowerCase();

                        bool matchTipo =
                            _filtroTipoComprobante == 'TODOS' ||
                            tipo == _filtroTipoComprobante;
                        bool matchEstado =
                            _filtroEstadoPago == 'TODOS' ||
                            estado == _filtroEstadoPago;
                        bool matchProv =
                            _busquedaProveedor.isEmpty ||
                            prov.contains(_busquedaProveedor.toLowerCase());

                        bool matchFecha = true;
                        if (_filtroFechas != null &&
                            data['fechaEmision'] != null) {
                          final Timestamp ts = data['fechaEmision'];
                          final DateTime dt = ts.toDate();
                          matchFecha =
                              dt.isAfter(_filtroFechas!.start) &&
                              dt.isBefore(
                                _filtroFechas!.end.add(const Duration(days: 1)),
                              );
                        }

                        return matchTipo &&
                            matchEstado &&
                            matchProv &&
                            matchFecha;
                      }).toList();

                      if (facturas.isEmpty) {
                        return const Center(
                          child: Text(
                            'No se encontraron comprobantes con los filtros aplicados.',
                            style: TextStyle(color: Colors.blueGrey),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFFF1F5F9),
                            ),
                            columns: const [
                              DataColumn(
                                label: Text(
                                  'Fecha Emisión',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'Vencimiento',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'Tipo / N° Comprobante',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'Proveedor / CUIT',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'Neto Gravado',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'IVA Total',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'Percepciones',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'Total',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'Estado',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  'Acciones',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                            rows: facturas.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final DateTime fecha =
                                  (data['fechaEmision'] as Timestamp).toDate();
                              final DateTime? fechaVenc =
                                  data['fechaVencimiento'] != null
                                  ? (data['fechaVencimiento'] as Timestamp)
                                        .toDate()
                                  : null;
                              final String idComprobante = doc.id;
                              final String estado =
                                  data['estadoPago'] ?? 'PENDIENTE';
                              final double total =
                                  (data['montoTotal'] as num?)?.toDouble() ??
                                  0.0;
                              final double neto =
                                  (data['netoGravadoTotal'] as num?)
                                      ?.toDouble() ??
                                  0.0;
                              final double iva =
                                  (data['ivaTotal'] as num?)?.toDouble() ?? 0.0;
                              final double percepciones =
                                  (data['percepcionesTotal'] as num?)
                                      ?.toDouble() ??
                                  0.0;

                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      DateFormat('dd/MM/yyyy').format(fecha),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      fechaVenc != null
                                          ? DateFormat(
                                              'dd/MM/yyyy',
                                            ).format(fechaVenc)
                                          : '-',
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${data['tipoComprobante']} ${data['numeroComprobante']}',
                                    ),
                                  ),
                                  DataCell(
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data['razonSocialProveedor'] ?? '-',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'CUIT: ${data['cuitProveedor'] ?? '-'}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(_currencyFormat.format(neto))),
                                  DataCell(Text(_currencyFormat.format(iva))),
                                  DataCell(
                                    Text(_currencyFormat.format(percepciones)),
                                  ),
                                  DataCell(
                                    Text(
                                      _currencyFormat.format(total),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(_buildBadgeEstado(estado)),
                                  DataCell(
                                    Row(
                                      children: [
                                        if (estado != 'PAGADO')
                                          IconButton(
                                            icon: const Icon(
                                              Icons.payments_rounded,
                                              color: Colors.green,
                                            ),
                                            tooltip:
                                                'Generar Orden de Pago (OP)',
                                            onPressed: () => _abrirOrdenDePago(
                                              context,
                                              data,
                                              idComprobante,
                                            ),
                                          ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.assignment_return_rounded,
                                            color: Colors.orange,
                                          ),
                                          tooltip: 'Generar NC / ND',
                                          onPressed: () =>
                                              _generarNotaCreditoDebito(
                                                context,
                                                data,
                                                idComprobante,
                                              ),
                                        ),
                                      ],
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
        ),
      ),
    );
  }

  // 🛠️ COMPONENTE: BARRA DE FILTROS
  Widget _construirBarraFiltros() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por Proveedor / CUIT',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _busquedaProveedor = val),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _filtroTipoComprobante,
            items: [
              'TODOS',
              'Factura A',
              'Factura B',
              'Factura C',
              'Ticket X',
              'Interno',
            ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (val) => setState(() => _filtroTipoComprobante = val!),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _filtroEstadoPago,
            items: [
              'TODOS',
              'PENDIENTE',
              'PARCIAL',
              'PAGADO',
            ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (val) => setState(() => _filtroEstadoPago = val!),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(
              _filtroFechas == null
                  ? 'Filtrar Fecha'
                  : '${DateFormat('dd/MM').format(_filtroFechas!.start)} - ${DateFormat('dd/MM').format(_filtroFechas!.end)}',
            ),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _filtroFechas = picked);
            },
          ),
          if (_filtroFechas != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.red),
              onPressed: () => setState(() => _filtroFechas = null),
            ),
        ],
      ),
    );
  }

  Widget _buildBadgeEstado(String estado) {
    Color color;
    switch (estado) {
      case 'PAGADO':
        color = Colors.green;
        break;
      case 'PARCIAL':
        color = Colors.orange;
        break;
      default:
        color = Colors.red;
    }
    return Chip(
      label: Text(
        estado,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color),
    );
  }

  // 📊 NAVEGACIÓN AL LIBRO IVA COMPRAS
  void _abrirLibroIvaCompras(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LibroIvaComprasPage()),
    );
  }

  // 👥 APERTURA DEL EXPLORADOR DE PADRÓN DE PROVEEDORES
  void _abrirPadronProveedores(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ProveedoresExploradorPadronDialog(),
    );
  }

  // 📄 APERTURA DE LA CARGA DE FACTURAS
  void _abrirDialogoNuevaFactura(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const NuevaFacturaCompraDialog(),
    );
  }

  // 💳 APERTURA DE LA EMISIÓN DE ORDEN DE PAGO
  void _abrirOrdenDePago(
    BuildContext context,
    Map<String, dynamic> factura,
    String facturaId,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          OrdenPagoDialog(factura: factura, facturaId: facturaId),
    );
  }

  // 🔄 NOTAS DE CRÉDITO / DÉBITO
  void _generarNotaCreditoDebito(
    BuildContext context,
    Map<String, dynamic> factura,
    String facturaId,
  ) {
    // Lógica para registrar Nota de Crédito/Débito en Cta Cte Proveedores
  }
}