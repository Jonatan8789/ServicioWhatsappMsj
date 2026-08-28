import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ExploradorVentasPage extends StatefulWidget {
  const ExploradorVentasPage({Key? key}) : super(key: key);

  @override
  State<ExploradorVentasPage> createState() => _ExploradorVentasPageState();
}

class _ExploradorVentasPageState extends State<ExploradorVentasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _filtroEstado = 'Todos';

  void _mostrarTicketFiscalDialog(Map<String, dynamic> venta) {
    final bool esFiscal = venta['cae'] != null && venta['cae'] != 'NO_FISCAL_X';
    final int tipoComp = venta['tipoComprobanteLegal'] ?? 11;
    String tipoLetra = 'C';
    if (tipoComp == 1) tipoLetra = 'A';
    if (tipoComp == 6) tipoLetra = 'B';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: esFiscal ? Colors.indigo : Colors.amber.shade900),
            const SizedBox(width: 8),
            Text(esFiscal ? 'Comprobante Fiscal ARCA' : 'Comprobante X (No Fiscal)'),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2), borderRadius: BorderRadius.circular(8)),
                  child: Text(esFiscal ? 'FACTURA $tipoLetra' : 'TICKET X', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
              ),
              const Divider(height: 24),
              Text('N° Comprobante: ${esFiscal ? "${venta['puntoVentaLegal']?.toString().padLeft(4, '0') ?? '0001'}-${venta['nroFacturaLegal']?.toString().padLeft(8, '0') ?? '00000000'}" : "X-00000000"}'),
              Text('Fecha: ${venta['fecha'] != null ? (venta['fecha'] as Timestamp).toDate().toString().substring(0, 16) : ''}'),
              if (venta['socio_id'] != null) Text('Cliente / DNI: ${venta['socio_id']}'),
              const Divider(),
              Text('Monto Total: \$${(venta['total'] as num?)?.toStringAsFixed(2) ?? '0.00'} ARS', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: esFiscal ? Colors.grey.shade100 : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: esFiscal ? Colors.grey.shade300 : Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(esFiscal ? 'CAE: ${venta['cae'] ?? 'N/A'}' : 'DOCUMENTO NO FISCAL', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (esFiscal) Text('Vencimiento CAE: ${venta['vencimientoCae'] ?? 'N/A'}'),
                    const SizedBox(height: 6),
                    Text(esFiscal ? 'Comprobante Autorizado Electrónicamente por ARCA' : 'Documento de Control Interno sin Validez Fiscal', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
            onPressed: () => _generarEImprimirPdfTicket(venta),
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Imprimir / PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _generarEImprimirPdfTicket(Map<String, dynamic> venta) async {
    final pdf = pw.Document();
    final bool esFiscal = venta['cae'] != null && venta['cae'] != 'NO_FISCAL_X';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('OQUA CLUB DEPORTIVO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.SizedBox(height: 4),
              pw.Text(esFiscal ? 'COMPROBANTE FISCAL' : 'TICKET X - NO FISCAL', style: pw.TextStyle(fontSize: 10)),
              pw.Divider(),
              pw.Text('Monto Total: \$${(venta['total'] as num?)?.toStringAsFixed(2) ?? '0.00'} ARS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 8),
              pw.Text('Fecha: ${venta['fecha'] != null ? (venta['fecha'] as Timestamp).toDate().toString().substring(0, 16) : ''}', style: const pw.TextStyle(fontSize: 9)),
              if (venta['socio_id'] != null) pw.Text('DNI/Cliente: ${venta['socio_id']}', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(),
              pw.Text(esFiscal ? 'CAE: ${venta['cae'] ?? ''}' : 'DOCUMENTO DE CONTROL INTERNO', style: pw.TextStyle(fontSize: 8)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // ❌ ANULACIÓN DIRECTA DE COMPROBANTE NO FISCAL (TICKET X) SIN NOTA DE CRÉDITO
  Future<void> _anularTicketNoFiscalDirecto(String ventaId, Map<String, dynamic> venta) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Comprobante X'),
        content: const Text('¿Confirmás la anulación de este ticket no fiscal? Se reintegrará el stock y se descontará de la caja.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular Directamente', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      WriteBatch batch = _firestore.batch();
      final double total = (venta['total'] as num?)?.toDouble() ?? 0.0;
      final String? cajaId = venta['cajaId'];

      // 1. Reintegrar productos al stock
      final List items = venta['items'] ?? [];
      for (var item in items) {
        if (item['es_producto_fisico'] == true && item['id'] != null) {
          final int cant = item['cantidad'] ?? 1;
          DocumentReference prodRef = _firestore.collection('inventario_general').doc(item['id']);
          batch.update(prodRef, {'stockActual': FieldValue.increment(cant)});
        }
      }

      // 2. Descontar del total de caja si la caja existe
      if (cajaId != null) {
        DocumentReference cajaRef = _firestore.collection('control_cajas').doc(cajaId);
        String medio = venta['medio_pago'] ?? 'Efectivo ARS';
        String campo = 'totalEfectivoARS';
        if (medio == 'Efectivo USD') campo = 'totalEfectivoUSD';
        if (medio == 'Mercado Pago') campo = 'totalMercadoPago';
        if (medio == 'Tarjeta Débito') campo = 'totalTarjetaDebito';
        if (medio == 'Tarjeta Crédito') campo = 'totalTarjetaCredito';
        if (medio == 'Transferencia Bancaria') campo = 'totalTransferencia';
        if (medio == 'Cuenta Corriente') campo = 'totalCtaCte';

        batch.update(cajaRef, {campo: FieldValue.increment(-total)});
      }

      // 3. Marcar ticket como anulado
      DocumentReference ventaRef = _firestore.collection('ventas_buffet').doc(ventaId);
      batch.update(ventaRef, {
        'estadoAjuste': 'Anulado Directo (Sin NC)',
        'anulado': true,
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Ticket X anulado y stock reintegrado.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error anulando ticket: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _mostrarDialogoNotaCreditoDebito(String ventaId, Map<String, dynamic> venta) {
    bool esCredito = true;
    bool reintegrarStock = true;
    final motivoCtrl = TextEditingController(text: 'Anulación/Ajuste de Comprobante Fiscal');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Generar Ajuste Fiscal ARCA (NC / ND)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Comprobante Original: PV ${venta['puntoVentaLegal']?.toString().padLeft(4, '0') ?? '0001'}-${venta['nroFacturaLegal']?.toString().padLeft(8, '0') ?? '0000'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Monto a Ajustar: \$${(venta['total'] as num?)?.toStringAsFixed(2) ?? "0.00"} ARS'),
              const Divider(height: 24),
              DropdownButtonFormField<bool>(
                value: esCredito,
                decoration: const InputDecoration(labelText: 'Tipo de Ajuste', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: true, child: Text('Nota de Crédito (NC - Anular / Devolver)')),
                  DropdownMenuItem(value: false, child: Text('Nota de Débito (ND - Cobro Adicional)')),
                ],
                onChanged: (v) => setModalState(() => esCredito = v!),
              ),
              const SizedBox(height: 12),
              TextField(controller: motivoCtrl, decoration: const InputDecoration(labelText: 'Motivo del Ajuste', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              if (esCredito)
                CheckboxListTile(
                  title: const Text('Reintegrar Productos al Stock Central'),
                  subtitle: const Text('Suma las unidades físicas de vuelta al inventario'),
                  value: reintegrarStock,
                  activeColor: Colors.teal,
                  onChanged: (v) => setModalState(() => reintegrarStock = v!),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () async {
                Navigator.pop(ctx);
                await _procesarEmitirAjusteArca(
                  ventaId: ventaId,
                  venta: venta,
                  esCredito: esCredito,
                  reintegrarStock: reintegrarStock,
                  motivo: motivoCtrl.text.trim(),
                );
              },
              child: const Text('Emitir a ARCA', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _procesarEmitirAjusteArca({
    required String ventaId,
    required Map<String, dynamic> venta,
    required bool esCredito,
    required bool reintegrarStock,
    required String motivo,
  }) async {
    try {
      final double monto = (venta['total'] as num?)?.toDouble() ?? 0.0;
      final int nroFacturaOrig = venta['nroFacturaLegal'] ?? 0;
      final int ptoVentaOrig = venta['puntoVentaLegal'] ?? 1;
      final int tipoCompOrig = venta['tipoComprobanteLegal'] ?? 11;

      final callable = FirebaseFunctions.instance.httpsCallable('emitirNotaCreditoDebitoArca');
      final resp = await callable.call({
        'monto': monto,
        'puntoVenta': ptoVentaOrig,
        'comprobanteAsociadoTipo': tipoCompOrig,
        'comprobanteAsociadoNro': nroFacturaOrig,
        'esCredito': esCredito,
      });

      final resData = resp.data;

      if (resData['success'] == true) {
        WriteBatch batch = _firestore.batch();

        if (esCredito && reintegrarStock && venta['items'] != null) {
          final List items = venta['items'];
          for (var item in items) {
            if (item['es_producto_fisico'] == true && item['id'] != null) {
              final int cant = item['cantidad'] ?? 1;
              DocumentReference prodRef = _firestore.collection('inventario_general').doc(item['id']);
              batch.update(prodRef, {'stockActual': FieldValue.increment(cant)});
            }
          }
        }

        DocumentReference ajusteRef = _firestore.collection('ajustes_fiscales_nc_nd').doc();
        batch.set(ajusteRef, {
          'ventaOriginalId': ventaId,
          'tipoAjuste': esCredito ? 'Nota de Crédito' : 'Nota de Débito',
          'cae': resData['cae'],
          'vencimientoCae': resData['vencimientoCae'],
          'nroComprobante': resData['nroComprobante'],
          'tipoComprobanteLegal': resData['tipoComprobante'],
          'monto': monto,
          'motivo': motivo,
          'fecha': DateTime.now(),
        });

        DocumentReference ventaRef = _firestore.collection('ventas_buffet').doc(ventaId);
        batch.update(ventaRef, {
          'estadoAjuste': esCredito ? 'Anulado con NC' : 'Ajustado con ND',
          'nc_nd_cae': resData['cae'],
          'nc_nd_nro': resData['nroComprobante'],
        });

        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green.shade800, content: Text('✅ ${esCredito ? "Nota de Crédito" : "Nota de Débito"} autorizada por ARCA (CAE: ${resData['cae']})')),
          );
        }
      } else {
        throw Exception(resData['error']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade900, content: Text('❌ Error emitiendo NC/ND en ARCA: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Explorador de Ventas & Facturación POS'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                const Text('Filtrar Estado ARCA: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                ChoiceChip(label: const Text('Todos'), selected: _filtroEstado == 'Todos', onSelected: (_) => setState(() => _filtroEstado = 'Todos')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('🟢 Fiscalizados'), selected: _filtroEstado == 'Fiscalizados', selectedColor: Colors.green.shade100, onSelected: (_) => setState(() => _filtroEstado = 'Fiscalizados')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('🔴 Pendientes / No Fiscales'), selected: _filtroEstado == 'Pendientes', selectedColor: Colors.red.shade100, onSelected: (_) => setState(() => _filtroEstado = 'Pendientes')),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('ventas_buffet').orderBy('fecha', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final bool fiscalizado = data['fiscalizado'] == true;
                  if (_filtroEstado == 'Fiscalizados') return fiscalizado;
                  if (_filtroEstado == 'Pendientes') return !fiscalizado;
                  return true;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('No hay ventas registradas con este filtro.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final venta = doc.data() as Map<String, dynamic>;
                    final bool fiscalizado = venta['fiscalizado'] == true;
                    final String? estadoAjuste = venta['estadoAjuste'];

                    final double total = (venta['total'] as num?)?.toDouble() ?? 0.0;
                    final String medioPago = venta['medio_pago'] ?? 'Efectivo';
                    final List items = venta['items'] ?? [];
                    final String detalleItems = items.map((it) => '${it['cantidad']}x ${it['nombre']}').join(', ');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: fiscalizado ? Colors.green.shade300 : Colors.red.shade300,
                          width: 1.5,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      fiscalizado ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                      color: fiscalizado ? Colors.green : Colors.orange,
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Total: \$${total.toStringAsFixed(2)} | $medioPago | ${venta['nombreCajaTerminal'] ?? "General"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: fiscalizado ? Colors.green.shade50 : Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: fiscalizado ? Colors.green : Colors.orange),
                                  ),
                                  child: Text(
                                    fiscalizado ? (estadoAjuste ?? 'FISCALIZADO') : (estadoAjuste ?? 'NO FISCAL / TICKET X'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: fiscalizado ? Colors.green.shade900 : Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Detalle: $detalleItems', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            const Divider(height: 20),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (fiscalizado) ...[
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo),
                                    onPressed: () => _mostrarTicketFiscalDialog(venta),
                                    icon: const Icon(Icons.print_rounded, size: 16),
                                    label: const Text('Ver / Reimprimir Ticket'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800, foregroundColor: Colors.white),
                                    onPressed: () => _mostrarDialogoNotaCreditoDebito(doc.id, venta),
                                    icon: const Icon(Icons.assignment_return_rounded, size: 16),
                                    label: const Text('Generar NC / ND (ARCA)'),
                                  ),
                                ] else ...[
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo),
                                    onPressed: () => _mostrarTicketFiscalDialog(venta),
                                    icon: const Icon(Icons.print_rounded, size: 16),
                                    label: const Text('Ver Ticket X'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800, foregroundColor: Colors.white),
                                    onPressed: () => _anularTicketNoFiscalDirecto(doc.id, venta),
                                    icon: const Icon(Icons.cancel_rounded, size: 16),
                                    label: const Text('Anular Venta Directa (Sin NC)'),
                                  ),
                                ],
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
    );
  }
}