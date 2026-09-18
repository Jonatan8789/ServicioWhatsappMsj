import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/data_explorer.dart';
import 'nueva_factura_compra_dialog.dart';
import 'orden_pago_dialog.dart';
import 'nota_credito_debito_compra_dialog.dart';
import 'proveedores_explorador_padron_dialog.dart';
import 'libro_iva_compras_page.dart';

class _FacturaCompra {
  final String id;
  final Map<String, dynamic> data;
  final DateTime fechaEmision;
  final DateTime? fechaVencimiento;
  final String tipoComprobante;
  final String razonSocialProveedor;
  final String cuitProveedor;
  final double neto;
  final double iva;
  final double percepciones;
  final double total;
  final String estado;

  _FacturaCompra(this.id, this.data)
    : fechaEmision = (data['fechaEmision'] as Timestamp).toDate(),
      fechaVencimiento = (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      tipoComprobante =
          '${data['tipoComprobante'] ?? ''} ${data['numeroComprobante'] ?? ''}',
      razonSocialProveedor = data['razonSocialProveedor'] ?? '-',
      cuitProveedor = data['cuitProveedor'] ?? '-',
      neto = (data['netoGravadoTotal'] as num?)?.toDouble() ?? 0.0,
      iva = (data['ivaTotal'] as num?)?.toDouble() ?? 0.0,
      percepciones = (data['percepcionesTotal'] as num?)?.toDouble() ?? 0.0,
      total = (data['montoTotal'] as num?)?.toDouble() ?? 0.0,
      estado = data['estadoPago'] ?? 'PENDIENTE';
}

class ProveedoresComprasPage extends StatefulWidget {
  const ProveedoresComprasPage({super.key});

  @override
  State<ProveedoresComprasPage> createState() => _ProveedoresComprasPageState();
}

class _ProveedoresComprasPageState extends State<ProveedoresComprasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _filtroTipoComprobante = 'TODOS';
  String _filtroEstadoPago = 'TODOS';

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
            _construirBarraFiltrosTipoEstado(),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  // 🚀 Antes esto cargaba TODA la colección sin límite y
                  // filtraba todo en el cliente. Ahora se acota el traído
                  // (últimos 1000 comprobantes, orden por fecha) y se usa el
                  // mismo DataExplorer reutilizable de los otros exploradores
                  // (búsqueda, orden por columna, columnas visibles, CSV).
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('compras_facturas')
                        .orderBy('fechaEmision', descending: true)
                        .limit(1000)
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

                      final facturas = snapshot.data!.docs
                          .map(
                            (d) => _FacturaCompra(
                              d.id,
                              d.data() as Map<String, dynamic>,
                            ),
                          )
                          .where((f) {
                            final bool matchTipo =
                                _filtroTipoComprobante == 'TODOS' ||
                                f.tipoComprobante.startsWith(
                                  _filtroTipoComprobante,
                                );
                            final bool matchEstado =
                                _filtroEstadoPago == 'TODOS' ||
                                f.estado == _filtroEstadoPago;
                            return matchTipo && matchEstado;
                          })
                          .toList();

                      if (facturas.isEmpty) {
                        return const Center(
                          child: Text(
                            'No se encontraron comprobantes con los filtros aplicados.',
                            style: TextStyle(color: Colors.blueGrey),
                          ),
                        );
                      }

                      return DataExplorer<_FacturaCompra>(
                        items: facturas,
                        nombreArchivoCsv: 'facturas_compra',
                        fechaDe: (f) => f.fechaEmision,
                        columnas: [
                          ColumnaExplorador(
                            etiqueta: 'Fecha Emisión',
                            texto: (f) =>
                                DateFormat('dd/MM/yyyy').format(f.fechaEmision),
                            orden: (f) => f.fechaEmision,
                          ),
                          ColumnaExplorador(
                            etiqueta: 'Vencimiento',
                            texto: (f) => f.fechaVencimiento != null
                                ? DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(f.fechaVencimiento!)
                                : '-',
                          ),
                          ColumnaExplorador(
                            etiqueta: 'Tipo / N° Comprobante',
                            texto: (f) => f.tipoComprobante,
                          ),
                          ColumnaExplorador(
                            etiqueta: 'Proveedor',
                            texto: (f) => f.razonSocialProveedor,
                          ),
                          ColumnaExplorador(
                            etiqueta: 'CUIT',
                            texto: (f) => f.cuitProveedor,
                            visibleInicialmente: false,
                          ),
                          ColumnaExplorador(
                            etiqueta: 'Neto Gravado',
                            texto: (f) => _currencyFormat.format(f.neto),
                            orden: (f) => f.neto,
                          ),
                          ColumnaExplorador(
                            etiqueta: 'IVA Total',
                            texto: (f) => _currencyFormat.format(f.iva),
                            orden: (f) => f.iva,
                          ),
                          ColumnaExplorador(
                            etiqueta: 'Percepciones',
                            texto: (f) => _currencyFormat.format(f.percepciones),
                            orden: (f) => f.percepciones,
                            visibleInicialmente: false,
                          ),
                          ColumnaExplorador(
                            etiqueta: 'Total',
                            texto: (f) => _currencyFormat.format(f.total),
                            orden: (f) => f.total,
                          ),
                          ColumnaExplorador(
                            etiqueta: 'Estado',
                            texto: (f) => f.estado,
                          ),
                        ],
                        accionesFila: (context, f) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (f.estado != 'PAGADO')
                              IconButton(
                                icon: const Icon(
                                  Icons.payments_rounded,
                                  color: Colors.green,
                                ),
                                tooltip: 'Generar Orden de Pago (OP)',
                                onPressed: () =>
                                    _abrirOrdenDePago(context, f.data, f.id),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.assignment_return_rounded,
                                color: Colors.orange,
                              ),
                              tooltip: 'Generar NC / ND',
                              onPressed: () => _generarNotaCreditoDebito(
                                context,
                                f.data,
                                f.id,
                              ),
                            ),
                            if ((f.data['comprobanteUrl'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              IconButton(
                                icon: const Icon(
                                  Icons.attach_file_rounded,
                                  color: Colors.indigo,
                                ),
                                tooltip: 'Ver comprobante adjunto',
                                onPressed: () =>
                                    _abrirComprobanteAdjunto(f.data),
                              ),
                          ],
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

  Widget _construirBarraFiltrosTipoEstado() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, color: Colors.blueGrey),
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
          const SizedBox(width: 16),
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
          const Spacer(),
          const Text(
            'Últimos 1000 comprobantes • usá "Buscar" y "Rango de fechas" abajo para acotar más',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _abrirLibroIvaCompras(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LibroIvaComprasPage()),
    );
  }

  void _abrirPadronProveedores(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ProveedoresExploradorPadronDialog(),
    );
  }

  void _abrirDialogoNuevaFactura(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const NuevaFacturaCompraDialog(),
    );
  }

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

  void _generarNotaCreditoDebito(
    BuildContext context,
    Map<String, dynamic> factura,
    String facturaId,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => NotaCreditoDebitoCompraDialog(
        factura: factura,
        facturaId: facturaId,
      ),
    );
  }

  Future<void> _abrirComprobanteAdjunto(Map<String, dynamic> factura) async {
    final String url = (factura['comprobanteUrl'] as String?) ?? '';
    if (url.isEmpty) return;
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Comprobante Adjunto'),
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
