import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../shared/csv_utils.dart';
import '../../shared/csv_download.dart';
import '../../shared/libro_iva_digital_export.dart';

class _VentaFiscal {
  final DateTime fecha;
  final String origen;
  final String concepto;
  final String medioPago;
  final String? cae;
  final double monto;
  // 🧾 Campos adicionales sólo para el export del Libro de IVA Digital
  // (no se muestran en la tabla en pantalla, que ya andaba bien sin ellos).
  final int? tipoComprobanteLegal;
  final int? puntoVentaLegal;
  final int? nroFacturaLegal;
  final String? socioId;

  _VentaFiscal({
    required this.fecha,
    required this.origen,
    required this.concepto,
    required this.medioPago,
    required this.cae,
    required this.monto,
    this.tipoComprobanteLegal,
    this.puntoVentaLegal,
    this.nroFacturaLegal,
    this.socioId,
  });
}

/// Libro IVA Ventas — antes leía de 'ventas_facturas', una colección que
/// ningún flujo del sistema escribe (quedaba siempre vacía). Los
/// comprobantes fiscales reales con CAE se generan en dos lugares:
/// ventas_buffet (POS + inscripciones de torneo, campo 'fiscalizado') y
/// socios/{id}/cuenta_corriente (cobro de cuota social, campo
/// 'facturadoArca'). Esta pantalla ahora une ambos. No se muestra un
/// desglose de neto/IVA por alícuota porque la facturación ARCA del club
/// se emite como Monotributista (Factura C, sin discriminar IVA) — mostrar
/// esa columna con datos inventados sería peor que no mostrarla.
class LibroIvaVentasPage extends StatefulWidget {
  const LibroIvaVentasPage({super.key});

  @override
  State<LibroIvaVentasPage> createState() => _LibroIvaVentasPageState();
}

class _LibroIvaVentasPageState extends State<LibroIvaVentasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _fechaInicio = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  DateTime _fechaFin = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'es_AR',
    symbol: '\$',
  );

  List<_VentaFiscal>? _ultimaListaCargada;
  bool _exportandoLibroIva = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Libro IVA Ventas (Comprobantes con CAE)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _ultimaListaCargada == null
                ? null
                : () => _exportarCSV(context, _ultimaListaCargada!),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text(
              'Exportar CSV',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            onPressed: _ultimaListaCargada == null || _exportandoLibroIva
                ? null
                : () => _exportarLibroIvaDigital(context, _ultimaListaCargada!),
            icon: _exportandoLibroIva
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.description_outlined, size: 20),
            label: const Text(
              'Libro IVA Digital (TXT)',
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
            _buildBarraPeriodo(),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('ventas_buffet')
                    .where('fiscalizado', isEqualTo: true)
                    .where(
                      'fecha',
                      isGreaterThanOrEqualTo: Timestamp.fromDate(_fechaInicio),
                    )
                    .where(
                      'fecha',
                      isLessThanOrEqualTo: Timestamp.fromDate(
                        _fechaFin.add(const Duration(days: 1)),
                      ),
                    )
                    .snapshots(),
                builder: (context, snapshotVentas) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collectionGroup('cuenta_corriente')
                        .where('facturadoArca', isEqualTo: true)
                        .where(
                          'fecha',
                          isGreaterThanOrEqualTo: Timestamp.fromDate(
                            _fechaInicio,
                          ),
                        )
                        .where(
                          'fecha',
                          isLessThanOrEqualTo: Timestamp.fromDate(
                            _fechaFin.add(const Duration(days: 1)),
                          ),
                        )
                        .snapshots(),
                    builder: (context, snapshotCuotas) {
                      if (snapshotVentas.hasError || snapshotCuotas.hasError) {
                        return Center(
                          child: Text(
                            'Error al cargar comprobantes: ${snapshotVentas.error ?? snapshotCuotas.error}',
                          ),
                        );
                      }
                      if (!snapshotVentas.hasData || !snapshotCuotas.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final List<_VentaFiscal> lista = [];

                      for (var doc in snapshotVentas.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final Timestamp? t = data['fecha'] as Timestamp?;
                        if (t == null) continue;
                        final List items = data['items'] ?? [];
                        final String detalle = items.isNotEmpty
                            ? items
                                  .map((it) => '${it['cantidad']}x ${it['nombre']}')
                                  .join(' | ')
                            : 'Venta POS / Buffet';
                        lista.add(
                          _VentaFiscal(
                            fecha: t.toDate(),
                            origen: 'POS / Buffet / Torneo',
                            concepto: detalle,
                            medioPago: data['medio_pago']?.toString() ?? '-',
                            cae: data['cae']?.toString(),
                            monto: (data['total'] as num?)?.toDouble() ?? 0.0,
                            tipoComprobanteLegal: (data['tipoComprobanteLegal'] as num?)?.toInt(),
                            puntoVentaLegal: (data['puntoVentaLegal'] as num?)?.toInt(),
                            nroFacturaLegal: (data['nroFacturaLegal'] as num?)?.toInt(),
                            socioId: data['socio_id']?.toString(),
                          ),
                        );
                      }

                      for (var doc in snapshotCuotas.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final Timestamp? t = data['fecha'] as Timestamp?;
                        if (t == null) continue;
                        // 🚨 El socioId de una cuota no está en el propio
                        // documento: es el padre de la subcolección
                        // (socios/{socioId}/cuenta_corriente/{este_doc}).
                        final String? socioIdCuota = doc.reference.parent.parent?.id;
                        lista.add(
                          _VentaFiscal(
                            fecha: t.toDate(),
                            origen: 'Cuota Social',
                            concepto:
                                data['concepto']?.toString() ??
                                data['tipo']?.toString() ??
                                'Cobro de Cuota',
                            medioPago: data['medioPago']?.toString() ?? '-',
                            cae: data['cae']?.toString(),
                            monto: ((data['monto'] as num?)?.toDouble() ?? 0.0)
                                .abs(),
                            tipoComprobanteLegal: (data['tipoComprobanteLegal'] as num?)?.toInt(),
                            puntoVentaLegal: (data['puntoVentaLegal'] as num?)?.toInt(),
                            nroFacturaLegal: (data['nroFacturaLegal'] as num?)?.toInt(),
                            socioId: socioIdCuota,
                          ),
                        );
                      }

                      lista.sort((a, b) => b.fecha.compareTo(a.fecha));

                      // 🚨 No se puede llamar setState del State padre de
                      // forma síncrona acá (este callback corre dentro del
                      // build() de un StreamBuilder anidado): se difiere al
                      // post-frame para que el botón "Exportar CSV" del
                      // AppBar reaccione una vez que llegan datos reales.
                      //
                      // 🐛 Antes comparaba sólo por longitud, lo que no
                      // detecta que el usuario cambió el rango de fechas
                      // mientras el callback estaba en cola: se podía
                      // exportar una lista de un período distinto al que se
                      // ve en pantalla. Ahora se marca con qué rango se
                      // calculó y sólo se aplica si ese rango sigue vigente.
                      final DateTime fechaInicioCalculo = _fechaInicio;
                      final DateTime fechaFinCalculo = _fechaFin;
                      if (_ultimaListaCargada?.length != lista.length) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (_fechaInicio != fechaInicioCalculo ||
                              _fechaFin != fechaFinCalculo) {
                            return;
                          }
                          setState(() => _ultimaListaCargada = lista);
                        });
                      } else {
                        _ultimaListaCargada = lista;
                      }

                      final double totalFacturado = lista.fold(
                        0.0,
                        (acc, v) => acc + v.monto,
                      );

                      return Column(
                        children: [
                          _buildTarjetasResumen(
                            total: totalFacturado,
                            cantidad: lista.length,
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: lista.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No hay comprobantes fiscales (con CAE) emitidos en el período seleccionado.',
                                        ),
                                      )
                                    : LayoutBuilder(
                                        builder: (context, constraints) {
                                          // 📱 Debajo de este ancho la tabla
                                          // sólo se veía vía scroll
                                          // horizontal, con texto diminuto:
                                          // se reemplaza por una lista de
                                          // tarjetas apiladas.
                                          if (constraints.maxWidth < 700) {
                                            return _buildListaTarjetas(lista);
                                          }
                                          return SingleChildScrollView(
                                            scrollDirection: Axis.vertical,
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: DataTable(
                                            headingRowColor:
                                                WidgetStateProperty.all(
                                                  const Color(0xFFF1F5F9),
                                                ),
                                            columns: const [
                                              DataColumn(
                                                label: Text(
                                                  'Fecha',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Origen',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Concepto',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Medio de Pago',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'CAE',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Monto',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            rows: lista.map((v) {
                                              return DataRow(
                                                cells: [
                                                  DataCell(
                                                    Text(
                                                      DateFormat(
                                                        'dd/MM/yyyy HH:mm',
                                                      ).format(v.fecha),
                                                    ),
                                                  ),
                                                  DataCell(Text(v.origen)),
                                                  DataCell(
                                                    ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                            maxWidth: 280,
                                                          ),
                                                      child: Text(
                                                        v.concepto,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(Text(v.medioPago)),
                                                  DataCell(
                                                    Text(v.cae ?? '-'),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      _currencyFormat.format(
                                                        v.monto,
                                                      ),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
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

  // 📱 Vista de tarjetas para pantallas angostas — reemplaza la tabla que
  // sólo se veía haciendo scroll horizontal con texto diminuto.
  Widget _buildListaTarjetas(List<_VentaFiscal> lista) {
    return ListView.separated(
      itemCount: lista.length,
      separatorBuilder: (_, __) => const Divider(height: 20),
      itemBuilder: (context, i) {
        final v = lista[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(v.fecha),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    _currencyFormat.format(v.monto),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                v.concepto,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('Origen: ${v.origen}', style: const TextStyle(fontSize: 12)),
                  Text('Medio: ${v.medioPago}', style: const TextStyle(fontSize: 12)),
                  Text('CAE: ${v.cae ?? '-'}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBarraPeriodo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, color: Colors.indigo),
          const SizedBox(width: 10),
          Text(
            'Período Ventas: ${DateFormat('dd/MM/yyyy').format(_fechaInicio)} al ${DateFormat('dd/MM/yyyy').format(_fechaFin)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range_rounded),
            label: const Text('Cambiar Período'),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: DateTimeRange(
                  start: _fechaInicio,
                  end: _fechaFin,
                ),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() {
                  _fechaInicio = picked.start;
                  _fechaFin = picked.end;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetasResumen({required double total, required int cantidad}) {
    return Row(
      children: [
        _tarjetaTotal('Comprobantes Emitidos', cantidad.toDouble(), Colors.blueGrey, esMoneda: false),
        const SizedBox(width: 12),
        _tarjetaTotal('TOTAL FACTURADO (CAE)', total, Colors.teal, esDestacado: true),
      ],
    );
  }

  Widget _tarjetaTotal(
    String titulo,
    double valor,
    MaterialColor color, {
    bool esDestacado = false,
    bool esMoneda = true,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: esDestacado ? color.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: esDestacado ? color.shade900 : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: esDestacado ? Colors.white70 : Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                esMoneda ? _currencyFormat.format(valor) : valor.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: esDestacado ? Colors.white : color.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🧾 EXPORT LIBRO DE IVA DIGITAL (formato ARCA, ex-CITI) — ver
  // lib/shared/libro_iva_digital_export.dart para la especificación de
  // campos. Sólo incluye Factura A/B con CAE real; Factura C
  // (Monotributo) queda afuera porque no discrimina IVA y no forma parte
  // del Libro de IVA de nadie.
  Future<void> _exportarLibroIvaDigital(
    BuildContext context,
    List<_VentaFiscal> lista,
  ) async {
    setState(() => _exportandoLibroIva = true);
    try {
      final incluidas = lista.where((v) {
        final tipo = v.tipoComprobanteLegal;
        final bool esFiscal = v.cae != null && v.cae != 'NO_FISCAL' && v.cae != 'ERROR_CAE';
        return esFiscal &&
            (tipo == 1 || tipo == 6) &&
            v.puntoVentaLegal != null &&
            v.nroFacturaLegal != null;
      }).toList();

      if (incluidas.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No hay comprobantes Factura A/B en este período — el Libro de '
                'IVA sólo aplica a Responsable Inscripto. Si el club todavía '
                'factura como Monotributista (Factura C), no corresponde '
                'generar este archivo.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final double alicuota = await _obtenerAlicuotaConfigurada();

      // Resuelve el DNI del comprador con caché por socioId (varias ventas
      // pueden repetir el mismo socio en el período).
      final Map<String, String?> cacheDni = {};
      Future<String?> dniDe(String? socioId) async {
        if (socioId == null) return null;
        if (cacheDni.containsKey(socioId)) return cacheDni[socioId];
        final snap = await _firestore.collection('socios').doc(socioId).get();
        String? dni;
        if (snap.exists) {
          final data = snap.data();
          dni = data?['dni']?.toString();
        }
        cacheDni[socioId] = dni;
        return dni;
      }

      final List<ComprobanteVentaIva> comprobantes = [];
      for (final v in incluidas) {
        final double impNeto = v.tipoComprobanteLegal == 11
            ? v.monto
            : v.monto / (1 + alicuota / 100);
        final double impIva = v.monto - impNeto;
        comprobantes.add(
          ComprobanteVentaIva(
            fecha: v.fecha,
            tipoComprobante: v.tipoComprobanteLegal!,
            puntoVenta: v.puntoVentaLegal!,
            numero: v.nroFacturaLegal!,
            dniComprador: await dniDe(v.socioId),
            nombreComprador: 'CONSUMIDOR FINAL',
            total: v.monto,
            importeNetoGravado: impNeto,
            importeIva: impIva,
            alicuotaPorcentaje: alicuota,
          ),
        );
      }

      final String sufijo = DateFormat('yyyy-MM').format(_fechaInicio);
      descargarCsv('LIBRO_IVA_DIGITAL_VENTAS_CBTE_$sufijo.txt', generarVentasCbte(comprobantes));
      descargarCsv('LIBRO_IVA_DIGITAL_VENTAS_ALICUOTAS_$sufijo.txt', generarVentasAlicuotas(comprobantes));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Generados ${comprobantes.length} comprobante(s) — revisá los campos antes de importarlos al Portal IVA.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el Libro de IVA: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportandoLibroIva = false);
    }
  }

  Future<double> _obtenerAlicuotaConfigurada() async {
    try {
      final doc = await _firestore
          .collection('configuraciones_fiscales')
          .doc('arca_reglas')
          .get();
      return (doc.data()?['alicuotaIvaPorcentaje'] as num?)?.toDouble() ?? 21.0;
    } catch (_) {
      return 21.0;
    }
  }

  void _exportarCSV(BuildContext context, List<_VentaFiscal> lista) {
    final filas = lista
        .map(
          (v) => [
            DateFormat('dd/MM/yyyy HH:mm').format(v.fecha),
            v.origen,
            v.concepto,
            v.medioPago,
            v.cae ?? '',
            v.monto.toStringAsFixed(2),
          ],
        )
        .toList();

    final csv = generarCsv(
      ['Fecha', 'Origen', 'Concepto', 'Medio de Pago', 'CAE', 'Monto'],
      filas,
    );

    try {
      descargarCsv(
        'libro_iva_ventas_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
        csv,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }
}
