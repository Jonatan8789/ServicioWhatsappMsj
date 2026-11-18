import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProveedoresAbmDialog extends StatefulWidget {
  final Map<String, dynamic>? proveedorExistente;
  final String? proveedorId;

  const ProveedoresAbmDialog({
    super.key,
    this.proveedorExistente,
    this.proveedorId,
  });

  @override
  State<ProveedoresAbmDialog> createState() => _ProveedoresAbmDialogState();
}

class _ProveedoresAbmDialogState extends State<ProveedoresAbmDialog> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controllers / Variables de Formulario
  late TextEditingController _razonSocialCtrl;
  late TextEditingController _nombreFantasiaCtrl;
  late TextEditingController _cuitCtrl;
  late TextEditingController _telefonoCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _calleCtrl;
  late TextEditingController _localidadCtrl;
  late TextEditingController _cbuCtrl;
  late TextEditingController _aliasCtrl;
  late TextEditingController _bancoCtrl;

  String _condicionIVA = 'Responsable Inscripto';
  String _jurisdiccionIIBB = 'ARBA (Bs. As.)';
  String _medioPagoHabitual = 'Transferencia Bancaria';
  int _diasVencimientoFactura = 30;
  String _provincia = 'Buenos Aires';

  final List<String> _provinciasArg = [
    'Buenos Aires',
    'CABA',
    'Catamarca',
    'Chaco',
    'Chubut',
    'Córdoba',
    'Corrientes',
    'Entre Ríos',
    'Formosa',
    'Jujuy',
    'La Pampa',
    'La Rioja',
    'Mendoza',
    'Misiones',
    'Neuquén',
    'Río Negro',
    'Salta',
    'San Juan',
    'San Luis',
    'Santa Cruz',
    'Santa Fe',
    'Santiago del Estero',
    'Tierra del Fuego',
    'Tucumán',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.proveedorExistente;
    _razonSocialCtrl = TextEditingController(text: p?['razonSocial'] ?? '');
    _nombreFantasiaCtrl = TextEditingController(
      text: p?['nombreFantasia'] ?? '',
    );
    _cuitCtrl = TextEditingController(text: p?['cuit'] ?? '');
    _telefonoCtrl = TextEditingController(text: p?['telefono'] ?? '');
    _emailCtrl = TextEditingController(text: p?['email'] ?? '');
    _calleCtrl = TextEditingController(text: p?['calle'] ?? '');
    _localidadCtrl = TextEditingController(text: p?['localidad'] ?? '');
    _cbuCtrl = TextEditingController(text: p?['cbu'] ?? '');
    _aliasCtrl = TextEditingController(text: p?['alias'] ?? '');
    _bancoCtrl = TextEditingController(text: p?['banco'] ?? '');

    if (p != null) {
      _condicionIVA = p['condicionIVA'] ?? _condicionIVA;
      _jurisdiccionIIBB = p['jurisdiccionIIBB'] ?? _jurisdiccionIIBB;
      _medioPagoHabitual = p['medioPagoHabitual'] ?? _medioPagoHabitual;
      _diasVencimientoFactura = p['diasVencimientoFactura'] ?? 30;
      _provincia = p['provincia'] ?? _provincia;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool esEdicion = widget.proveedorId != null;

    return AlertDialog(
      title: Text(
        esEdicion ? 'Editar Proveedor' : 'Nuevo Proveedor en Padrón',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1️⃣ DATOS PRINCIPALES Y DNI/CUIT
                _seccionTitulo('Datos Identificatorios'),
                _filaCampos(
                  flexes: const [2, 2, 1],
                  [
                    TextFormField(
                      controller: _razonSocialCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Razón Social *',
                        isDense: true,
                      ),
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                    ),
                    TextFormField(
                      controller: _nombreFantasiaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre Fantasía',
                        isDense: true,
                      ),
                    ),
                    TextFormField(
                      controller: _cuitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'CUIT / CUIL *',
                        isDense: true,
                      ),
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2️⃣ DATOS FISCALES E IMPOSITIVOS
                _seccionTitulo('Información Impositiva & Fiscal'),
                _filaCampos([
                  DropdownButtonFormField<String>(
                    value: _condicionIVA,
                    decoration: const InputDecoration(
                      labelText: 'Condición IVA',
                      isDense: true,
                    ),
                    items:
                        [
                              'Responsable Inscripto',
                              'Monotributo',
                              'Exento',
                              'Consumidor Final',
                            ]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _condicionIVA = v!),
                  ),
                  DropdownButtonFormField<String>(
                    value: _jurisdiccionIIBB,
                    decoration: const InputDecoration(
                      labelText: 'Jurisdicción IIBB',
                      isDense: true,
                    ),
                    items:
                        [
                              'ARBA (Bs. As.)',
                              'AGIP (CABA)',
                              'Convenio Multilateral',
                              'Exento',
                            ]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _jurisdiccionIIBB = v!),
                  ),
                ]),
                const SizedBox(height: 12),

                // 3️⃣ CONDICIONES COMERCIALES (DÍAS DE CRÉDITO Y MEDIO DE PAGO)
                _seccionTitulo('Condiciones Comerciales & Pago'),
                _filaCampos([
                  TextFormField(
                    initialValue: _diasVencimientoFactura.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Días Vencimiento Facturas',
                      suffixText: 'Días',
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        _diasVencimientoFactura = int.tryParse(v) ?? 0,
                  ),
                  DropdownButtonFormField<String>(
                    value: _medioPagoHabitual,
                    decoration: const InputDecoration(
                      labelText: 'Medio de Pago Habitual',
                      isDense: true,
                    ),
                    items:
                        [
                              'Transferencia Bancaria',
                              'Efectivo',
                              'Cheque Propio',
                              'ECHEQ',
                            ]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _medioPagoHabitual = v!),
                  ),
                ]),
                const SizedBox(height: 12),

                // 4️⃣ DATOS BANCARIOS
                _filaCampos([
                  TextFormField(
                    controller: _bancoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Banco',
                      isDense: true,
                    ),
                  ),
                  TextFormField(
                    controller: _cbuCtrl,
                    decoration: const InputDecoration(
                      labelText: 'CBU / CVU',
                      isDense: true,
                    ),
                  ),
                  TextFormField(
                    controller: _aliasCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Alias CBU',
                      isDense: true,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // 5️⃣ DOMICILIO Y CONTACTO
                _seccionTitulo('Domicilio & Contacto'),
                _filaCampos(
                  flexes: const [2, 1, 1],
                  [
                    TextFormField(
                      controller: _calleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Dirección / Calle',
                        isDense: true,
                      ),
                    ),
                    TextFormField(
                      controller: _localidadCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Localidad',
                        isDense: true,
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      value: _provincia,
                      decoration: const InputDecoration(
                        labelText: 'Provincia',
                        isDense: true,
                      ),
                      items: _provinciasArg
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setState(() => _provincia = v!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _filaCampos([
                  TextFormField(
                    controller: _telefonoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono de Contacto',
                      isDense: true,
                    ),
                  ),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email para Envío de OP',
                      isDense: true,
                    ),
                  ),
                ]),
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
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
          ),
          onPressed: _guardarProveedor,
          child: Text(esEdicion ? 'Actualizar' : 'Guardar Proveedor'),
        ),
      ],
    );
  }

  // 📱 Reemplaza los ~6 Row(Expanded, Expanded, ...) de este formulario que
  // antes quedaban ilegibles en un teléfono: por debajo de 500px de ancho
  // (el diálogo ya está acotado a 850px como máximo) cada campo pasa a
  // ocupar su propio renglón en vez de compartir uno apretado.
  Widget _filaCampos(List<Widget> campos, {List<int>? flexes}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool esMovil = constraints.maxWidth < 500;
        if (esMovil) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < campos.length; i++) ...[
                campos[i],
                if (i < campos.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (int i = 0; i < campos.length; i++) ...[
              Expanded(
                flex: flexes != null ? flexes[i] : 1,
                child: campos[i],
              ),
              if (i < campos.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _seccionTitulo(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
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

  Future<void> _guardarProveedor() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'razonSocial': _razonSocialCtrl.text.trim(),
      'nombreFantasia': _nombreFantasiaCtrl.text.trim(),
      'cuit': _cuitCtrl.text.trim(),
      'telefono': _telefonoCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'calle': _calleCtrl.text.trim(),
      'localidad': _localidadCtrl.text.trim(),
      'provincia': _provincia,
      'condicionIVA': _condicionIVA,
      'jurisdiccionIIBB': _jurisdiccionIIBB,
      'medioPagoHabitual': _medioPagoHabitual,
      'diasVencimientoFactura': _diasVencimientoFactura,
      'banco': _bancoCtrl.text.trim(),
      'cbu': _cbuCtrl.text.trim(),
      'alias': _aliasCtrl.text.trim(),
      'actualizadoEl': FieldValue.serverTimestamp(),
    };

    if (widget.proveedorId != null) {
      await _firestore
          .collection('proveedores')
          .doc(widget.proveedorId)
          .update(data);
    } else {
      await _firestore.collection('proveedores').add(data);
    }

    if (mounted) Navigator.pop(context);
  }
}
