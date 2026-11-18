import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../shared/csv_utils.dart';
import '../../shared/csv_download.dart';
import '../../services/auditoria_service.dart';

class ExploradorVentasPage extends StatefulWidget {
  const ExploradorVentasPage({Key? key}) : super(key: key);

  @override
  State<ExploradorVentasPage> createState() => _ExploradorVentasPageState();
}

class _ExploradorVentasPageState extends State<ExploradorVentasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _filtroEstado = 'Todos';
  String _filtroMedioPago = 'Todos';
  String _busqueda = '';
  // 🚨 Antes esta pantalla traía TODA la colección 'ventas_buffet' sin
  // ningún límite de fecha, con .snapshots() en vivo — cada apertura leía
  // más y más documentos a medida que se acumulaban meses de ventas
  // (costo y lentitud creciente sin techo). Ahora el rango de fechas es
  // real y va contra Firestore (no un filtro client-side sobre datos ya
  // traídos), con 30 días como ventana por defecto.
  DateTimeRange _rangoFechas = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  Future<Map<String, String>> _headersWhatsapp() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _reenviarComprobantePorWhatsapp(
    Map<String, dynamic> venta,
    Map<String, dynamic>? socioData,
  ) async {
    final String? telefono = socioData?['telefono'];
    if (telefono == null || telefono.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente no tiene un teléfono registrado.')),
      );
      return;
    }

    String limpio = telefono.replaceAll(RegExp(r'\D'), '');
    if (limpio.startsWith('0')) limpio = limpio.substring(1);
    if (limpio.startsWith('15')) limpio = limpio.substring(2);
    if (!limpio.startsWith('54')) limpio = '549$limpio';

    final bool esFiscal = venta['cae'] != null && venta['cae'] != 'NO_FISCAL_X';
    final List items = venta['items'] ?? [];
    final double total = (venta['total'] as num?)?.toDouble() ?? 0.0;

    final buffer = StringBuffer();
    buffer.writeln('📄 *COMPROBANTE DE PAGO - OQUA CLUB DEPORTIVO*');
    buffer.writeln('----------------------------------------');
    if (socioData != null) {
      buffer.writeln(
        '👤 *Cliente:* ${socioData['nombre'] ?? ''} ${socioData['apellido'] ?? ''}'.trim(),
      );
    }
    buffer.writeln('💳 *Medio de Pago:* ${venta['medio_pago'] ?? '-'}');
    buffer.writeln(
      '🧾 *Tipo:* ${esFiscal ? "Factura Fiscal ARCA (CAE: ${venta['cae']})" : "Comprobante X (No Fiscal)"}',
    );
    buffer.writeln('----------------------------------------');
    buffer.writeln('*Detalle:*');
    for (var it in items) {
      buffer.writeln('• ${it['nombre']} x${it['cantidad'] ?? 1}: \$${it['precio']} ARS');
    }
    buffer.writeln('----------------------------------------');
    buffer.writeln('💰 *TOTAL:* \$${total.toStringAsFixed(2)} ARS');

    try {
      final resp = await http.post(
        Uri.parse('https://servicio-whatsapp-oqua.onrender.com/send-whatsapp'),
        headers: await _headersWhatsapp(),
        body: jsonEncode({'phone': limpio, 'message': buffer.toString()}),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              resp.statusCode == 200
                  ? '✅ Comprobante reenviado por WhatsApp.'
                  : '⚠️ No se pudo reenviar (${resp.statusCode}).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Error al reenviar: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _buscarSocio(String? socioId) async {
    if (socioId == null || socioId.isEmpty) return null;
    try {
      final snap = await _firestore.collection('socios').doc(socioId).get();
      return snap.exists ? snap.data() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportarCsv(BuildContext context) async {
    final snap = await _firestore
        .collection('ventas_buffet')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(_rangoFechas.start))
        .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(
          DateTime(_rangoFechas.end.year, _rangoFechas.end.month, _rangoFechas.end.day, 23, 59, 59),
        ))
        .orderBy('fecha', descending: true)
        .limit(3000)
        .get();
    final docs = snap.docs.where((d) {
      final data = d.data();
      final bool fiscalizado = data['fiscalizado'] == true;
      if (_filtroEstado == 'Fiscalizados') return fiscalizado;
      if (_filtroEstado == 'Pendientes') return !fiscalizado;
      return true;
    });

    final filas = docs.map((d) {
      final v = d.data();
      final List items = v['items'] ?? [];
      final detalle = items.map((it) => '${it['cantidad']}x ${it['nombre']}').join(' | ');
      final fecha = (v['fecha'] as Timestamp?)?.toDate();
      return [
        fecha != null ? DateFormat('dd/MM/yyyy HH:mm').format(fecha) : '',
        (v['total'] as num?)?.toStringAsFixed(2) ?? '0.00',
        v['medio_pago'] ?? '',
        v['nombreCajaTerminal'] ?? '',
        v['fiscalizado'] == true ? 'Fiscalizado' : 'No Fiscal',
        v['cae'] ?? '',
        detalle,
      ];
    }).toList();

    final csv = generarCsv(
      ['Fecha', 'Total', 'Medio de Pago', 'Caja', 'Estado', 'CAE', 'Detalle'],
      filas,
    );

    try {
      descargarCsv(
        'ventas_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
        csv,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    }
  }

  Future<void> _mostrarTicketFiscalDialog(Map<String, dynamic> venta) async {
    final bool esFiscal = venta['cae'] != null && venta['cae'] != 'NO_FISCAL_X';
    final int tipoComp = venta['tipoComprobanteLegal'] ?? 11;
    String tipoLetra = 'C';
    if (tipoComp == 1) tipoLetra = 'A';
    if (tipoComp == 6) tipoLetra = 'B';

    final Map<String, dynamic>? socioData = await _buscarSocio(venta['socio_id']);
    final List items = venta['items'] ?? [];
    final bool anulado = venta['anulado'] == true;
    final String? estadoAjuste = venta['estadoAjuste'];
    final String? estadoPagoMP = venta['estadoPagoMP'];

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: esFiscal ? Colors.indigo : Colors.amber.shade900),
            const SizedBox(width: 8),
            Expanded(child: Text(esFiscal ? 'Comprobante Fiscal ARCA' : 'Comprobante X (No Fiscal)')),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (anulado || estadoAjuste != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Text(
                      '⚠️ ${estadoAjuste ?? "ANULADO"}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900),
                    ),
                  ),
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
                Text('Caja / Terminal: ${venta['nombreCajaTerminal'] ?? 'General'}'),
                if (venta['usuario'] != null) Text('Cajero: ${venta['usuario']}'),
                Text('Medio de Pago: ${venta['medio_pago'] ?? '-'}'),
                if (venta['origen_salón'] != null) Text('Origen: ${venta['origen_salón']}'),
                if (socioData != null)
                  Text('Cliente: ${socioData['nombre'] ?? ''} ${socioData['apellido'] ?? ''} (DNI ${socioData['dni'] ?? '-'})')
                else if (venta['socio_id'] != null)
                  Text('Cliente / ID: ${venta['socio_id']}'),
                const Divider(),
                const Text('Detalle de Ítems', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...items.map((it) {
                  final double precioUnit = (it['precio'] as num?)?.toDouble() ?? 0.0;
                  final int cant = (it['cantidad'] as num?)?.toInt() ?? 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text('${cant}x ${it['nombre'] ?? ''}', style: const TextStyle(fontSize: 13))),
                        Text('\$${(precioUnit * cant).toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  );
                }),
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
                if (estadoPagoMP != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: estadoPagoMP == 'Aprobado' ? Colors.blue.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: estadoPagoMP == 'Aprobado' ? Colors.blue.shade300 : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mercado Pago: $estadoPagoMP', style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (venta['mpPaymentId'] != null) Text('ID de pago: ${venta['mpPaymentId']}', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
                if (venta['nc_nd_cae'] != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ajuste ARCA: ${estadoAjuste ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('CAE Ajuste: ${venta['nc_nd_cae']}', style: const TextStyle(fontSize: 11)),
                        if (venta['nc_nd_nro'] != null) Text('N° Ajuste: ${venta['nc_nd_nro']}', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          if (socioData?['telefono'] != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade700),
              onPressed: () => _reenviarComprobantePorWhatsapp(venta, socioData),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Reenviar WhatsApp'),
            ),
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
    final List items = venta['items'] ?? [];

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
              pw.Text('Fecha: ${venta['fecha'] != null ? (venta['fecha'] as Timestamp).toDate().toString().substring(0, 16) : ''}', style: const pw.TextStyle(fontSize: 9)),
              if (venta['socio_id'] != null) pw.Text('DNI/Cliente: ${venta['socio_id']}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Medio de Pago: ${venta['medio_pago'] ?? '-'}', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: items.map((it) {
                  final double precioUnit = (it['precio'] as num?)?.toDouble() ?? 0.0;
                  final int cant = (it['cantidad'] as num?)?.toInt() ?? 1;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${cant}x ${it['nombre'] ?? ''}', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('\$${(precioUnit * cant).toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  );
                }).toList(),
              ),
              pw.Divider(),
              pw.Text('Monto Total: \$${(venta['total'] as num?)?.toStringAsFixed(2) ?? '0.00'} ARS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.Divider(),
              pw.Text(esFiscal ? 'CAE: ${venta['cae'] ?? ''}' : 'DOCUMENTO DE CONTROL INTERNO', style: pw.TextStyle(fontSize: 8)),
              if (esFiscal) pw.Text('Vto. CAE: ${venta['vencimientoCae'] ?? ''}', style: const pw.TextStyle(fontSize: 8)),
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
      await registrarAuditoria(
        accion: 'anular_venta_directa',
        entidad: 'ventas_buffet',
        entidadId: ventaId,
        detalle: {'total': total, 'medioPago': venta['medio_pago']},
      );

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
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Estado ARCA: ', style: TextStyle(fontWeight: FontWeight.bold)),
                ChoiceChip(label: const Text('Todos'), selected: _filtroEstado == 'Todos', onSelected: (_) => setState(() => _filtroEstado = 'Todos')),
                ChoiceChip(label: const Text('🟢 Fiscalizados'), selected: _filtroEstado == 'Fiscalizados', selectedColor: Colors.green.shade100, onSelected: (_) => setState(() => _filtroEstado = 'Fiscalizados')),
                ChoiceChip(label: const Text('🔴 Pendientes / No Fiscales'), selected: _filtroEstado == 'Pendientes', selectedColor: Colors.red.shade100, onSelected: (_) => setState(() => _filtroEstado = 'Pendientes')),
                const SizedBox(width: 12),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    initialValue: _filtroMedioPago,
                    decoration: const InputDecoration(
                      labelText: 'Medio de Pago',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      'Todos',
                      'Efectivo ARS',
                      'Efectivo USD',
                      'Mercado Pago',
                      'Tarjeta Débito',
                      'Tarjeta Crédito',
                      'Transferencia Bancaria',
                      'Cuenta Corriente',
                    ].map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setState(() => _filtroMedioPago = v!),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar producto, DNI o caja',
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final rango = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: _rangoFechas,
                    );
                    if (rango != null) setState(() => _rangoFechas = rango);
                  },
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    '${DateFormat('dd/MM/yy').format(_rangoFechas.start)} - ${DateFormat('dd/MM/yy').format(_rangoFechas.end)}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportarCsv(context),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Exportar CSV'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('ventas_buffet')
                  .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(_rangoFechas.start))
                  .where('fecha', isLessThanOrEqualTo: Timestamp.fromDate(
                    DateTime(_rangoFechas.end.year, _rangoFechas.end.month, _rangoFechas.end.day, 23, 59, 59),
                  ))
                  .orderBy('fecha', descending: true)
                  .limit(3000)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final bool fiscalizado = data['fiscalizado'] == true;
                  if (_filtroEstado == 'Fiscalizados' && !fiscalizado) return false;
                  if (_filtroEstado == 'Pendientes' && fiscalizado) return false;
                  if (_filtroMedioPago != 'Todos' && data['medio_pago'] != _filtroMedioPago) {
                    return false;
                  }
                  if (_busqueda.isNotEmpty) {
                    final List items = data['items'] ?? [];
                    final String textoBusqueda = [
                      ...items.map((it) => it['nombre']?.toString() ?? ''),
                      data['socio_id']?.toString() ?? '',
                      data['nombreCajaTerminal']?.toString() ?? '',
                    ].join(' ').toLowerCase();
                    if (!textoBusqueda.contains(_busqueda)) return false;
                  }
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
                    final bool anulado = venta['anulado'] == true || estadoAjuste != null;
                    final String? estadoPagoMP = venta['estadoPagoMP'];

                    return Opacity(
                      opacity: anulado ? 0.6 : 1.0,
                      child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: anulado
                              ? Colors.grey.shade400
                              : (fiscalizado ? Colors.green.shade300 : Colors.red.shade300),
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
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        fiscalizado ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                        color: fiscalizado ? Colors.green : Colors.orange,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Total: \$${total.toStringAsFixed(2)} | $medioPago | ${venta['nombreCajaTerminal'] ?? "General"}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            decoration: anulado ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (estadoPagoMP != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(
                                      estadoPagoMP == 'Aprobado' ? Icons.qr_code_2_rounded : Icons.hourglass_top_rounded,
                                      size: 18,
                                      color: estadoPagoMP == 'Aprobado' ? Colors.blue : Colors.grey,
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: anulado
                                        ? Colors.grey.shade200
                                        : (fiscalizado ? Colors.green.shade50 : Colors.orange.shade50),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: anulado ? Colors.grey.shade500 : (fiscalizado ? Colors.green : Colors.orange),
                                    ),
                                  ),
                                  child: Text(
                                    fiscalizado ? (estadoAjuste ?? 'FISCALIZADO') : (estadoAjuste ?? 'NO FISCAL / TICKET X'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: anulado
                                          ? Colors.grey.shade800
                                          : (fiscalizado ? Colors.green.shade900 : Colors.orange.shade900),
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
                                    onPressed: anulado ? null : () => _mostrarDialogoNotaCreditoDebito(doc.id, venta),
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
                                    onPressed: anulado ? null : () => _anularTicketNoFiscalDirecto(doc.id, venta),
                                    icon: const Icon(Icons.cancel_rounded, size: 16),
                                    label: const Text('Anular Venta Directa (Sin NC)'),
                                  ),
                                ],
                              ],
                            ),
                          ],
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
}