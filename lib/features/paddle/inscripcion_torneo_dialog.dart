import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class InscripcionTorneoDialog extends StatefulWidget {
  final String torneoId;
  final String nombreTorneo;
  final double precioInscripcion;

  const InscripcionTorneoDialog({
    super.key,
    required this.torneoId,
    this.nombreTorneo = 'Torneo de Pádel',
    this.precioInscripcion = 0.0,
  });

  @override
  State<InscripcionTorneoDialog> createState() =>
      _InscripcionTorneoDialogState();
}

class _InscripcionTorneoDialogState extends State<InscripcionTorneoDialog> {
  final _formKey = GlobalKey<FormState>();

  final _dni1Controller = TextEditingController();
  final _nombre1Controller = TextEditingController();
  final _telefono1Controller = TextEditingController();
  final _email1Controller = TextEditingController();
  final _club1Controller = TextEditingController();
  String _categoria1 = '5ta';
  bool _esSocio1 = false;
  bool _buscando1 = false;

  final _dni2Controller = TextEditingController();
  final _nombre2Controller = TextEditingController();
  final _telefono2Controller = TextEditingController();
  final _email2Controller = TextEditingController();
  final _club2Controller = TextEditingController();
  String _categoria2 = '5ta';
  bool _esSocio2 = false;
  bool _buscando2 = false;

  final _restriccionHorariaController = TextEditingController();

  // Cobro y Facturación
  String _metodoPago = 'Efectivo ARS';
  bool _registraPagoAhora = true;
  bool _emitirFacturaFiscal = false; // 👈 Alternar entre ARCA o Ticket X
  bool _guardando = false;

  final List<String> _categoriasPadel = [
    '1ra',
    '2da',
    '3ra',
    '4ta',
    '5ta',
    '6ta',
    '7ma',
    'Principiantes',
  ];

  @override
  void dispose() {
    _dni1Controller.dispose();
    _nombre1Controller.dispose();
    _telefono1Controller.dispose();
    _email1Controller.dispose();
    _club1Controller.dispose();
    _dni2Controller.dispose();
    _nombre2Controller.dispose();
    _telefono2Controller.dispose();
    _email2Controller.dispose();
    _club2Controller.dispose();
    _restriccionHorariaController.dispose();
    super.dispose();
  }

  Future<void> _buscarSocio(String dni, int jugadorNum) async {
    final dniLimpio = dni.trim().replaceAll('.', '');
    if (dniLimpio.isEmpty) return;

    setState(() {
      if (jugadorNum == 1) _buscando1 = true;
      if (jugadorNum == 2) _buscando2 = true;
    });

    try {
      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('socios')
          .where('dni', isEqualTo: dniLimpio)
          .limit(1)
          .get();

      if (query.docs.isEmpty && int.tryParse(dniLimpio) != null) {
        query = await FirebaseFirestore.instance
            .collection('socios')
            .where('dni', isEqualTo: int.parse(dniLimpio))
            .limit(1)
            .get();
      }

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data() as Map<String, dynamic>;
        final nombreCompleto =
            "${data['nombre'] ?? ''} ${data['apellido'] ?? ''}".trim();

        setState(() {
          if (jugadorNum == 1) {
            _nombre1Controller.text = nombreCompleto;
            _telefono1Controller.text = data['telefono'] ?? '';
            _email1Controller.text = data['email'] ?? '';
            _club1Controller.text = 'OQUA Club (Socio)';
            if (_categoriasPadel.contains(data['categoriaPaddle'])) {
              _categoria1 = data['categoriaPaddle'];
            }
            _esSocio1 = true;
          } else {
            _nombre2Controller.text = nombreCompleto;
            _telefono2Controller.text = data['telefono'] ?? '';
            _email2Controller.text = data['email'] ?? '';
            _club2Controller.text = 'OQUA Club (Socio)';
            if (_categoriasPadel.contains(data['categoriaPaddle'])) {
              _categoria2 = data['categoriaPaddle'];
            }
            _esSocio2 = true;
          }
        });
      } else {
        setState(() {
          if (jugadorNum == 1) _esSocio1 = false;
          if (jugadorNum == 2) _esSocio2 = false;
        });
      }
    } catch (e) {
      print("Error buscando socio: $e");
    } finally {
      setState(() {
        if (jugadorNum == 1) _buscando1 = false;
        if (jugadorNum == 2) _buscando2 = false;
      });
    }
  }

  Future<void> _guardarInscripcion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    final userActual = FirebaseAuth.instance.currentUser;

    try {
      final batch = FirebaseFirestore.instance.batch();

      final docInscripcionRef = FirebaseFirestore.instance
          .collection('torneos')
          .doc(widget.torneoId)
          .collection('parejas_inscriptas')
          .doc();

      final datosInscripcion = {
        'id': docInscripcionRef.id,
        'jugador1': {
          'dni': _dni1Controller.text.trim(),
          'nombreCompleto': _nombre1Controller.text.trim(),
          'telefono': _telefono1Controller.text.trim(),
          'email': _email1Controller.text.trim(),
          'clubOrigen': _club1Controller.text.trim(),
          'categoria': _categoria1,
          'esSocio': _esSocio1,
        },
        'jugador2': {
          'dni': _dni2Controller.text.trim(),
          'nombreCompleto': _nombre2Controller.text.trim(),
          'telefono': _telefono2Controller.text.trim(),
          'email': _email2Controller.text.trim(),
          'clubOrigen': _club2Controller.text.trim(),
          'categoria': _categoria2,
          'esSocio': _esSocio2,
        },
        'restriccionHoraria': _restriccionHorariaController.text.trim(),
        'montoTotal': widget.precioInscripcion,
        'estadoPago': _registraPagoAhora ? 'pagado' : 'pendiente',
        'metodoPago': _registraPagoAhora ? _metodoPago : 'Pendiente',
        'tipoComprobante': _emitirFacturaFiscal
            ? 'Factura Fiscal ARCA'
            : 'Comprobante X (No Fiscal)',
        'fechaInscripcion': FieldValue.serverTimestamp(),
      };

      batch.set(docInscripcionRef, datosInscripcion);

      String? ventaIdCreada;
      if (_registraPagoAhora && widget.precioInscripcion > 0) {
        final docCajaRef = FirebaseFirestore.instance
            .collection('ventas_buffet')
            .doc();
        ventaIdCreada = docCajaRef.id;

        batch.set(docCajaRef, {
          'id': docCajaRef.id,
          'items': [
            {
              'id': 'inscripcion_torneo_${widget.torneoId}',
              'nombre': 'Inscripción Torneo: ${widget.nombreTorneo}',
              'precio': widget.precioInscripcion,
              'cantidad': 1,
              'es_producto_fisico': false,
            },
          ],
          'total': widget.precioInscripcion,
          'medio_pago': _metodoPago,
          'usuario': userActual?.email ?? 'Administrador Central',
          'socio_id': _esSocio1 ? _dni1Controller.text.trim() : null,
          'origen_salón': 'Torneos Pádel',
          'tipoComprobante': _emitirFacturaFiscal
              ? 'Factura Fiscal ARCA'
              : 'Comprobante X (No Fiscal)',
          'fiscalizado': !_emitirFacturaFiscal,
          'cae': _emitirFacturaFiscal ? null : 'NO_FISCAL_X',
          'fecha': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // Si solicitó factura oficial ARCA, disparar la Cloud Function
      if (_registraPagoAhora && _emitirFacturaFiscal && ventaIdCreada != null) {
        _ejecutarFiscalizacionArca(
          ventaIdCreada,
          widget.precioInscripcion,
          _dni1Controller.text.trim(),
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _guardando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al inscribir pareja: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _ejecutarFiscalizacionArca(
    String ventaId,
    double total,
    String dni,
  ) async {
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('configuraciones_fiscales')
          .doc('arca_reglas')
          .get();

      if (!configDoc.exists) return;
      final configData = configDoc.data()!;

      var callable = FirebaseFunctions.instance.httpsCallable(
        'emitirFacturaArca',
      );
      final response = await callable.call({
        'total': total,
        'socioDni': dni,
        'cuit': configData['cuit'] ?? 0,
        'puntoVenta': configData['puntoVenta'] ?? 1,
        'comprobanteTipo': configData['comprobanteTipo'] ?? 11,
        'modoProduccion': configData['modoProduccion'] ?? false,
      });

      if (response.data['success'] == true) {
        await FirebaseFirestore.instance
            .collection('ventas_buffet')
            .doc(ventaId)
            .update({
              'fiscalizado': true,
              'cae': response.data['cae'],
              'vencimientoCae': response.data['vencimientoCae'],
              'nroFacturaLegal': response.data['nroFactura'],
              'puntoVentaLegal': response.data['puntoVenta'] ?? 1,
              'tipoComprobanteLegal': response.data['tipoComprobante'] ?? 11,
            });
      }
    } catch (e) {
      print("Error fiscalizando inscripción: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0A3B43);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inscripción de Pareja',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (widget.nombreTorneo.isNotEmpty)
            Text(
              widget.nombreTorneo,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // JUGADOR 1
                TextFormField(
                  controller: _dni1Controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'DNI Jugador 1',
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      color: primaryColor,
                    ),
                    suffixIcon: _buscando1
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search, color: primaryColor),
                            onPressed: () =>
                                _buscarSocio(_dni1Controller.text, 1),
                          ),
                  ),
                  onChanged: (val) {
                    if (val.length >= 7) _buscarSocio(val, 1);
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _nombre1Controller,
                        readOnly: _esSocio1,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Completo',
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _categoria1,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                        ),
                        items: _categoriasPadel
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _categoria1 = v!),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _telefono1Controller,
                        readOnly: _esSocio1,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono / WhatsApp',
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _club1Controller,
                        decoration: const InputDecoration(
                          labelText: 'Club / Localidad',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // JUGADOR 2
                TextFormField(
                  controller: _dni2Controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'DNI Jugador 2',
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      color: primaryColor,
                    ),
                    suffixIcon: _buscando2
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search, color: primaryColor),
                            onPressed: () =>
                                _buscarSocio(_dni2Controller.text, 2),
                          ),
                  ),
                  onChanged: (val) {
                    if (val.length >= 7) _buscarSocio(val, 2);
                  },
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _nombre2Controller,
                        readOnly: _esSocio2,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Completo',
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _categoria2,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                        ),
                        items: _categoriasPadel
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _categoria2 = v!),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _telefono2Controller,
                        readOnly: _esSocio2,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono / WhatsApp',
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _club2Controller,
                        decoration: const InputDecoration(
                          labelText: 'Club / Localidad',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _restriccionHorariaController,
                  decoration: const InputDecoration(
                    labelText: 'Restricción Horaria / Observaciones de Zonas',
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // SECTOR DE COBRO Y SELECCIÓN FISCAL
                if (widget.precioInscripcion > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Registrar Pago en Caja POS',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Switch(
                        value: _registraPagoAhora,
                        activeColor: primaryColor,
                        onChanged: (v) =>
                            setState(() => _registraPagoAhora = v),
                      ),
                    ],
                  ),
                  if (_registraPagoAhora) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        children: [
                          // Selector Factura ARCA vs Ticket X
                          SwitchListTile(
                            title: Text(
                              _emitirFacturaFiscal
                                  ? 'Emitir Factura ARCA (Oficial)'
                                  : 'Comprobante X (No Fiscal)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              _emitirFacturaFiscal
                                  ? 'Solicita CAE oficial'
                                  : 'Registro en caja sin envío a ARCA',
                              style: const TextStyle(fontSize: 11),
                            ),
                            value: _emitirFacturaFiscal,
                            activeColor: Colors.indigo,
                            onChanged: (v) =>
                                setState(() => _emitirFacturaFiscal = v),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _metodoPago,
                            decoration: const InputDecoration(
                              labelText: 'Medio de Pago',
                            ),
                            items:
                                [
                                      'Efectivo ARS',
                                      'Mercado Pago',
                                      'MODO',
                                      'Tarjeta Débito',
                                      'Tarjeta Crédito',
                                      'Transferencia Bancaria',
                                    ]
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) => setState(() => _metodoPago = v!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
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
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          onPressed: _guardando ? null : _guardarInscripcion,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  _registraPagoAhora && widget.precioInscripcion > 0
                      ? 'Cobrar e Inscribir'
                      : 'Inscribir Pareja',
                ),
        ),
      ],
    );
  }
}
