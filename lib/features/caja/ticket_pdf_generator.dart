import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class TicketPdfGenerator {
  static Future<Uint8List> generarTicketBuffet(
    Map<String, dynamic> ventaData,
  ) async {
    final pdf = pw.Document();

    // Formato ticket térmico (aprox 80mm)
    final formatoThermal80mm = const PdfPageFormat(
      226,
      double.infinity,
      marginAll:
          5 *
          PdfPageFormat.mm, // Margen un poco más chico para aprovechar el ancho
    );

    // --- Extracción y formateo de datos ---
    final fechaTs = ventaData['fecha'];
    final DateTime dateTime = fechaTs != null
        ? fechaTs.toDate()
        : DateTime.now();
    final String fechaStr = DateFormat(
      'dd.MM.yyyy HH:mm:ss',
    ).format(dateTime); // Formato de la imagen

    final double total = (ventaData['total'] ?? 0).toDouble();
    final String medioPago = ventaData['medio_pago'] ?? 'Efectivo';
    final double entregado = (ventaData['dinero_entregado'] ?? total)
        .toDouble();
    final List<dynamic> items = ventaData['items'] ?? [];

    // Cálculos simulados para el desglose de IVA (Asumiendo IVA 21% incluido en el precio)
    final double ivaPorcentaje = 21.0;
    final double baseImponible = total / (1 + (ivaPorcentaje / 100));
    final double impuestoIva = total - baseImponible;

    // Número de documento / ID de venta simulado
    final String docNum = ventaData['id']?.toString().substring(0, 5) ?? '1042';

    pdf.addPage(
      pw.Page(
        pageFormat: formatoThermal80mm,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              // ==========================================
              // 1. QR SUPERIOR Y CÓDIGOS
              // ==========================================
              pw.Text('QR Oqua:', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),
              pw.Container(
                width: 80,
                height: 80,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: 'https://oqua.app/ticket/$docNum',
                  drawText: false,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'VERI*OQUA | TICKET_2026_$docNum',
                style: const pw.TextStyle(fontSize: 6),
              ),
              pw.SizedBox(height: 8),

              // ==========================================
              // 2. NOMBRE DE LA EMPRESA (Letra grande y negrita)
              // ==========================================
              pw.Text(
                'OQUA APP',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Club & Complejo',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // ==========================================
              // 3. DATOS DE LA EMPRESA
              // ==========================================
              pw.Text(
                'Av. Libertador 1234',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text('C1428 CABA', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Argentina', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                'CUIT: 30-12345678-9',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Email: contacto@oqua.app',
                style: const pw.TextStyle(fontSize: 8),
              ),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // ==========================================
              // 4. DATOS DEL TICKET (Empleado, Fecha, Caja)
              // ==========================================
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Empleado: Admin',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text('Documento', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Fecha: $fechaStr',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    'n.º: $docNum',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Caja: 1',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // ==========================================
              // 5. TABLA DE PRODUCTOS
              // ==========================================
              pw.Row(
                children: [
                  pw.SizedBox(
                    width: 25,
                    child: pw.Text(
                      'Cant.',
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'Artículo / \nservicio',
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 35,
                    child: pw.Text(
                      'Precio\nunitario',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 35,
                    child: pw.Text(
                      'Precio\ntotal',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),

              ...items.map((item) {
                final int cant = item['cantidad'] ?? 1;
                final double prec = (item['precio'] ?? 0).toDouble();
                final String nombre = item['nombre'] ?? '';
                final double subtotal = cant * prec;

                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.SizedBox(
                        width: 25,
                        child: pw.Text(
                          '$cant',
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          nombre,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.SizedBox(
                        width: 35,
                        child: pw.Text(
                          prec.toStringAsFixed(2),
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.SizedBox(
                        width: 35,
                        child: pw.Text(
                          subtotal.toStringAsFixed(2),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // ==========================================
              // 6. TOTAL
              // ==========================================
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total:',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$ ${total.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // ==========================================
              // 7. DESGLOSE DE IMPUESTOS (IVA)
              // ==========================================
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'IVA %',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'B.I. \$',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'Impuesto\n\$',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'Total \$',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '21',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      baseImponible.toStringAsFixed(2),
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      impuestoIva.toStringAsFixed(2),
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      total.toStringAsFixed(2),
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // ==========================================
              // 8. METODO DE PAGO
              // ==========================================
              pw.Text(
                'Método de pago: $medioPago',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Pagado: \$ ${entregado.toStringAsFixed(2)}',
                style: const pw.TextStyle(fontSize: 8),
              ),

              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 12),

              // ==========================================
              // 9. LOGO FINAL (Texto estilizado)
              // ==========================================
              pw.Text(
                'OQUA APP',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors
                      .blue, // Dando el toque del logo inferior de la foto
                ),
              ),
              pw.SizedBox(height: 15),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
