import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Modelo auxiliar para el desglose dinámico de percepciones de IIBB
class ItemPercepcionIIBB {
  String jurisdiccion;
  double monto;

  ItemPercepcionIIBB({required this.jurisdiccion, this.monto = 0.0});
}

class NuevaFacturaCompraDialog extends StatefulWidget {
  const NuevaFacturaCompraDialog({super.key});

  @override
  State<NuevaFacturaCompraDialog> createState() =>
      _NuevaFacturaCompraDialogState();
}

class _NuevaFacturaCompraDialogState extends State<NuevaFacturaCompraDialog> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Selección de Proveedor
  String? _proveedorIdSeleccionado;
  Map<String, dynamic>? _proveedorData;

  // Cabecera
  String _tipoComprobante = 'Factura A';
  String _numeroComprobante = '';
  String _cuitProveedor = '';
  String _razonSocialProveedor = '';

  // Fechas
  DateTime _fechaEmision = DateTime.now();
  DateTime _fechaVencimiento = DateTime.now().add(const Duration(days: 30));

  // Desglose
  double _neto21 = 0.0;
  double _neto105 = 0.0;
  double _neto27 = 0.0;
  double _exento = 0.0;

  // Percepciones Nacionales
  double _percepcionIVA = 0.0;
  double _percepcionGanancias = 0.0;

  // Lista Dinámica de Percepciones IIBB por Jurisdicción
  final List<ItemPercepcionIIBB> _listaPercepcionesIIBB = [
    ItemPercepcionIIBB(jurisdiccion: 'ARBA (Bs. As.)'),
  ];

  final List<String> _jurisdiccionesDisponibles = [
    'ARBA (Bs. As.)',
    'AGIP (CABA)',
    'Córdoba',
    'Santa Fe',
    'Mendoza',
    'Entre Ríos',
    'Tucumán',
    'Salta',
    'Convenio Multilateral / Otra',
  ];

  // Métodos de cálculo acumulado
  double get _totalNeto => _neto21 + _neto105 + _neto27;
  double get _totalIVA =>
      (_neto21 * 0.21) + (_neto105 * 0.105) + (_neto27 * 0.27);
  double get _totalIIBB =>
      _listaPercepcionesIIBB.fold(0.0, (sum, item) => sum + item.monto);
  double get _totalPercepciones =>
      _percepcionIVA + _percepcionGanancias + _totalIIBB;
  double get _montoTotal =>
      _totalNeto + _totalIVA + _exento + _totalPercepciones;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.receipt_long_rounded, color: Colors.teal),
          SizedBox(width: 10),
          Text(
            'Carga Desagregada de Factura de Compra',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 850,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1️⃣ BUSCADOR DE PROVEEDORES DE PADRÓN
                _seccionTitulo('1. Selección de Proveedor (Padrón Central)'),
                _buildBuscadorProveedor(),
                if (_proveedorData != null) ...[
                  const SizedBox(height: 10),
                  _buildFichaResumenProveedor(),
                ],
                const SizedBox(height: 20),

                // 2️⃣ DATOS DE COMPROBANTE Y FECHAS
                _seccionTitulo('2. Datos del Comprobante & Fechas'),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _tipoComprobante,
                        decoration: const InputDecoration(
                          labelText: 'Tipo Comprobante',
                          isDense: true,
                        ),
                        items:
                            [
                                  'Factura A',
                                  'Factura B',
                                  'Factura C',
                                  'Ticket X',
                                  'Interno',
                                ]
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => setState(() => _tipoComprobante = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'N° Comprobante (Ej: 0001-00001234)',
                          isDense: true,
                        ),
                        validator: (v) => v!.isEmpty
                            ? 'Ingrese el número del comprobante'
                            : null,
                        onChanged: (v) => _numeroComprobante = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                        ),
                        label: Text(
                          'Emisión: ${DateFormat('dd/MM/yyyy').format(_fechaEmision)}',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _fechaEmision,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() {
                              _fechaEmision = picked;
                              final int dias =
                                  (_proveedorData?['diasVencimientoFactura']
                                          as num?)
                                      ?.toInt() ??
                                  30;
                              _fechaVencimiento = picked.add(
                                Duration(days: dias),
                              );
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.event_available_rounded,
                          size: 18,
                          color: Colors.orange,
                        ),
                        label: Text(
                          'Vencimiento: ${DateFormat('dd/MM/yyyy').format(_fechaVencimiento)}',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _fechaVencimiento,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null)
                            setState(() => _fechaVencimiento = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 3️⃣ DESGLOSE BASES IMPONIBLES E IVA
                _seccionTitulo(
                  '3. Desglose de Base Imponible e IVA (Libro Compras)',
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Neto Gravado 21%',
                          prefixText: '\$ ',
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            setState(() => _neto21 = double.tryParse(v) ?? 0.0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Neto Gravado 10.5%',
                          prefixText: '\$ ',
                          isDense: true,
                        ),
                        onChanged: (v) => setState(
                          () => _neto105 = double.tryParse(v) ?? 0.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Neto Gravado 27%',
                          prefixText: '\$ ',
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            setState(() => _neto27 = double.tryParse(v) ?? 0.0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Conceptos Exentos / No Gravados',
                    prefixText: '\$ ',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      setState(() => _exento = double.tryParse(v) ?? 0.0),
                ),
                const SizedBox(height: 20),

                // 4️⃣ PERCEPCIONES (CON LISTA DINÁMICA DE JURISDICCIONES IIBB)
                _seccionTitulo('4. Percepciones Sufridas en la Compra'),

                ..._listaPercepcionesIIBB.asMap().entries.map((entry) {
                  final int index = entry.key;
                  final ItemPercepcionIIBB item = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: item.jurisdiccion,
                            decoration: InputDecoration(
                              labelText: 'Jurisdicción IIBB #${index + 1}',
                              isDense: true,
                            ),
                            items: _jurisdiccionesDisponibles
                                .map(
                                  (j) => DropdownMenuItem(
                                    value: j,
                                    child: Text(j),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => item.jurisdiccion = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Monto Percepción',
                              prefixText: '\$ ',
                              isDense: true,
                            ),
                            onChanged: (v) => setState(
                              () => item.monto = double.tryParse(v) ?? 0.0,
                            ),
                          ),
                        ),
                        if (_listaPercepcionesIIBB.length > 1)
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle,
                              color: Colors.red,
                            ),
                            onPressed: () => setState(
                              () => _listaPercepcionesIIBB.removeAt(index),
                            ),
                          ),
                      ],
                    ),
                  );
                }),

                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _listaPercepcionesIIBB.add(
                        ItemPercepcionIIBB(jurisdiccion: 'AGIP (CABA)'),
                      );
                    });
                  },
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.teal,
                  ),
                  label: const Text(
                    '+ Agregar Otra Jurisdicción IIBB',
                    style: TextStyle(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // PERCEPCIONES NACIONALES
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Percepción IVA',
                          prefixText: '\$ ',
                          isDense: true,
                        ),
                        onChanged: (v) => setState(
                          () => _percepcionIVA = double.tryParse(v) ?? 0.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Percepción Ganancias',
                          prefixText: '\$ ',
                          isDense: true,
                        ),
                        onChanged: (v) => setState(
                          () =>
                              _percepcionGanancias = double.tryParse(v) ?? 0.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 5️⃣ RESUMEN CONSOLIDADO DE TOTALES
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Neto Gravado: \$${_totalNeto.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'IVA Crédito: \$${_totalIVA.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue,
                            ),
                          ),
                          Text(
                            'Percep. IIBB Total: \$${_totalIIBB.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL COMPROBANTE:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '\$${_montoTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _guardarFacturaCompra,
          child: const Text(
            'Guardar e Imputar Cta. Cte.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // AUXILIARES DE INTERFAZ
  Widget _buildBuscadorProveedor() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('proveedores')
          .orderBy('razonSocial')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Text(
            'No hay proveedores registrados. Utilice el botón "Padrón Proveedores (ABM)" para dar de alta uno.',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          );
        }

        return DropdownButtonFormField<String>(
          value: _proveedorIdSeleccionado,
          decoration: const InputDecoration(
            labelText: 'Seleccionar Proveedor del Padrón *',
            prefixIcon: Icon(Icons.store_rounded),
            isDense: true,
          ),
          items: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return DropdownMenuItem<String>(
              value: doc.id,
              child: Text('${data['razonSocial']} (CUIT: ${data['cuit']})'),
            );
          }).toList(),
          onChanged: (id) {
            final docSel = docs.firstWhere((d) => d.id == id);
            final data = docSel.data() as Map<String, dynamic>;

            setState(() {
              _proveedorIdSeleccionado = id;
              _proveedorData = data;
              _cuitProveedor = data['cuit'] ?? '';
              _razonSocialProveedor = data['razonSocial'] ?? '';

              if (data['jurisdiccionIIBB'] != null) {
                _listaPercepcionesIIBB[0].jurisdiccion =
                    data['jurisdiccionIIBB'];
              }

              final int dias =
                  (data['diasVencimientoFactura'] as num?)?.toInt() ?? 30;
              _fechaVencimiento = _fechaEmision.add(Duration(days: dias));
            });
          },
          validator: (v) => v == null ? 'Seleccione un proveedor' : null,
        );
      },
    );
  }

  Widget _buildFichaResumenProveedor() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Condición IVA: ${_proveedorData?['condicionIVA'] ?? '-'}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          Text(
            'Días Crédito: ${_proveedorData?['diasVencimientoFactura'] ?? 30} días',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          Text(
            'CBU/Alias: ${_proveedorData?['alias'] ?? _proveedorData?['cbu'] ?? 'No registrado'}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionTitulo(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }

  // GUARDADO ATÓMICO EN FIRESTORE E IMPUTACIÓN EN CTA CTE
  Future<void> _guardarFacturaCompra() async {
    if (!_formKey.currentState!.validate()) return;

    final batch = _firestore.batch();
    final docFacturaRef = _firestore.collection('compras_facturas').doc();

    final List<Map<String, dynamic>> iibbDesglosado = _listaPercepcionesIIBB
        .where((item) => item.monto > 0)
        .map((item) => {'jurisdiccion': item.jurisdiccion, 'monto': item.monto})
        .toList();

    final dataFactura = {
      'proveedorId': _proveedorIdSeleccionado,
      'tipoComprobante': _tipoComprobante,
      'numeroComprobante': _numeroComprobante,
      'cuitProveedor': _cuitProveedor,
      'razonSocialProveedor': _razonSocialProveedor,
      'fechaEmision': Timestamp.fromDate(_fechaEmision),
      'fechaVencimiento': Timestamp.fromDate(_fechaVencimiento),
      'netoGravado21': _neto21,
      'netoGravado105': _neto105,
      'netoGravado27': _neto27,
      'netoGravadoTotal': _totalNeto,
      'ivaTotal': _totalIVA,
      'exento': _exento,
      'percepcionesIIBBDesglose': iibbDesglosado,
      'percepcionIIBBTotal': _totalIIBB,
      'percepcionIVA': _percepcionIVA,
      'percepcionGanancias': _percepcionGanancias,
      'percepcionesTotal': _totalPercepciones,
      'montoTotal': _montoTotal,
      'saldoPendiente': _montoTotal,
      'estadoPago': 'PENDIENTE',
      'creadoEl': FieldValue.serverTimestamp(),
    };

    batch.set(docFacturaRef, dataFactura);

    // Impacto Transaccional en Cta. Cte. Proveedores
    final ctaCteRef = _firestore.collection('cta_cte_proveedores').doc();
    batch.set(ctaCteRef, {
      'proveedorId': _proveedorIdSeleccionado,
      'cuitProveedor': _cuitProveedor,
      'razonSocial': _razonSocialProveedor,
      'fecha': Timestamp.fromDate(_fechaEmision),
      'tipoMovimiento': 'COMPRA_FACTURA',
      'comprobanteId': docFacturaRef.id,
      'descripcion': 'Factura $_tipoComprobante N° $_numeroComprobante',
      'montoHaber': _montoTotal,
      'montoDebe': 0.0,
    });

    await batch.commit();
    if (mounted) Navigator.pop(context);
  }
}
