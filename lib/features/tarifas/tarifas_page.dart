import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'tarifa_model.dart';

class TarifasPage extends StatefulWidget {
  const TarifasPage({super.key});

  @override
  State<TarifasPage> createState() => _TarifasPageState();
}

class _TarifasPageState extends State<TarifasPage> {
  final _formKey = GlobalKey<FormState>();
  final _precioRegularController = TextEditingController();
  final _precioEfectivoController = TextEditingController();
  final _matriculaController = TextEditingController(text: '20000');
  final _leyendaPromoController = TextEditingController(
    text: 'Hasta 3 cuotas sin interés abonando Miércoles y Sábados',
  );

  List<String> _deportes = [
    'Natación / Pileta Libre',
    'Escuela de Natación',
    'Pádel',
  ];
  List<String> _frecuencias = [
    'Pase Libre Mensual',
    '2 veces a la semana',
    '3 veces a la semana',
    'Promo 3 Meses',
    'Promo 6 Meses',
  ];

  String? _deporteSel;
  String? _frecuenciaSel;
  DateTime _fechaDesde = DateTime.now();
  DateTime? _fechaHasta;
  bool _cargandoConstantes = true;

  // 🏷️ ESTADOS PARA PROMOCIONES
  bool _esPromocion = false;
  int _duracionMesesSel = 3;

  @override
  void initState() {
    super.initState();
    _cargarConstantes();
  }

  @override
  void dispose() {
    _precioRegularController.dispose();
    _precioEfectivoController.dispose();
    _matriculaController.dispose();
    _leyendaPromoController.dispose();
    super.dispose();
  }

  Future<void> _cargarConstantes() async {
    try {
      final configRef = FirebaseFirestore.instance.collection('configuracion');
      final resultados = await Future.wait([
        configRef.doc('deportes').get(),
        configRef.doc('frecuencias').get(),
        configRef.doc('matricula_anual').get(),
      ]);

      setState(() {
        if (resultados[0].exists && resultados[0].data()?['lista'] != null) {
          _deportes = List<String>.from(resultados[0].data()!['lista']);
        }
        if (resultados[1].exists && resultados[1].data()?['lista'] != null) {
          _frecuencias = List<String>.from(resultados[1].data()!['lista']);
        }
        if (resultados[2].exists) {
          _matriculaController.text = (resultados[2].data()?['monto'] ?? 20000)
              .toString();
        }
        _cargandoConstantes = false;
      });
    } catch (_) {
      setState(() => _cargandoConstantes = false);
    }
  }

  Future<void> _guardarMatricula() async {
    final monto = double.tryParse(_matriculaController.text.trim()) ?? 20000.0;
    await FirebaseFirestore.instance
        .collection('configuracion')
        .doc('matricula_anual')
        .set({'monto': monto, 'actualizado': DateTime.now()});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Valor de Matrícula Anual actualizado!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _guardarTarifa() async {
    if (!_formKey.currentState!.validate() ||
        _deporteSel == null ||
        _frecuenciaSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa Deporte y Frecuencia.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final pReg = double.tryParse(_precioRegularController.text.trim()) ?? 0.0;
    final pEf = double.tryParse(_precioEfectivoController.text.trim()) ?? pReg;

    final nuevoDocRef = FirebaseFirestore.instance.collection('tarifas').doc();
    final nuevaTarifa = TarifaModel(
      id: nuevoDocRef.id,
      deporte: _deporteSel!,
      frecuencia: _frecuenciaSel!,
      precioRegular: pReg,
      precioEfectivo: pEf,
      fechaDesde: _fechaDesde,
      fechaHasta: _fechaHasta,
      tipo: _esPromocion ? 'PROMOCION' : 'REGULAR',
      duracionMeses: _esPromocion ? _duracionMesesSel : 1,
      valorFinalTotal: _esPromocion ? (pReg * _duracionMesesSel) : null,
      leyendaPromocion: _esPromocion
          ? _leyendaPromoController.text.trim()
          : null,
    );

    await nuevoDocRef.set(nuevaTarifa.toFirestore());

    _precioRegularController.clear();
    _precioEfectivoController.clear();
    setState(() {
      _deporteSel = null;
      _frecuenciaSel = null;
      _esPromocion = false;
      _fechaDesde = DateTime.now();
      _fechaHasta = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Tarifa / Promoción guardada exitosamente!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoConstantes) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 1,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // CARD 1: MATRÍCULA ANUAL
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Matrícula Anual (Calendario)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF78350F),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _matriculaController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Valor Anual (\$)',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.badge),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber.shade800,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                    horizontal: 16,
                                  ),
                                ),
                                onPressed: _guardarMatricula,
                                child: const Text(
                                  'Guardar',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // CARD 2: ALTA DE TARIFA O PROMOCIÓN
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Definir Tarifa / Promoción',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                FilterChip(
                                  label: const Text('¿Es Promoción?'),
                                  selected: _esPromocion,
                                  selectedColor: Colors.amber.shade200,
                                  onSelected: (val) =>
                                      setState(() => _esPromocion = val),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Deporte / Programa',
                                border: OutlineInputBorder(),
                              ),
                              value: _deporteSel,
                              items: _deportes
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(d),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _deporteSel = val),
                            ),
                            const SizedBox(height: 16),

                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Frecuencia / Nombre Paquete',
                                border: OutlineInputBorder(),
                              ),
                              value: _frecuenciaSel,
                              items: _frecuencias
                                  .map(
                                    (f) => DropdownMenuItem(
                                      value: f,
                                      child: Text(f),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _frecuenciaSel = val),
                            ),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _precioRegularController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Tarjeta / Regular (\$)',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Requerido' : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _precioEfectivoController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Efectivo (\$)',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Requerido' : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // CAMPOS ADICIONALES DE PROMOCIÓN
                            if (_esPromocion) ...[
                              DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'Duración del Paquete Promocional',
                                  border: OutlineInputBorder(),
                                ),
                                value: _duracionMesesSel,
                                items: const [
                                  DropdownMenuItem(
                                    value: 3,
                                    child: Text('3 Meses'),
                                  ),
                                  DropdownMenuItem(
                                    value: 6,
                                    child: Text('6 Meses'),
                                  ),
                                ],
                                onChanged: (val) => setState(
                                  () => _duracionMesesSel = val ?? 3,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _leyendaPromoController,
                                decoration: const InputDecoration(
                                  labelText: 'Financiación / Leyenda',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // SELECTORES DE FECHA DE VIGENCIA
                            Row(
                              children: [
                                Expanded(
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Vigente Desde:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    subtitle: Text(
                                      DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_fechaDesde),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.calendar_today,
                                      color: Colors.teal,
                                    ),
                                    onTap: () async {
                                      final f = await showDatePicker(
                                        context: context,
                                        initialDate: _fechaDesde,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (f != null)
                                        setState(() => _fechaDesde = f);
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Vigente Hasta:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _fechaHasta != null
                                          ? DateFormat(
                                              'dd/MM/yyyy',
                                            ).format(_fechaHasta!)
                                          : 'Indefinido',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.event_busy,
                                      color: Colors.orange,
                                    ),
                                    onTap: () async {
                                      final f = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            _fechaHasta ??
                                            _fechaDesde.add(
                                              const Duration(days: 30),
                                            ),
                                        firstDate: _fechaDesde,
                                        lastDate: DateTime(2030),
                                      );
                                      if (f != null)
                                        setState(() => _fechaHasta = f);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                minimumSize: const Size.fromHeight(50),
                              ),
                              icon: const Icon(Icons.save, color: Colors.white),
                              label: const Text(
                                'Guardar Tarifa / Promoción',
                                style: TextStyle(color: Colors.white),
                              ),
                              onPressed: _guardarTarifa,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),

            // COLUMNA DERECHA: HISTORIAL Y VIGENCIAS (CONSULTA RESILIENTE)
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tarifario y Promociones Activas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('tarifas')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final docs = snapshot.data!.docs;
                          if (docs.isEmpty) {
                            return const Center(
                              child: Text(
                                'No hay tarifas ni promociones guardadas.',
                              ),
                            );
                          }

                          final listaTarifas = docs
                              .map(
                                (d) => TarifaModel.fromFirestore(
                                  d.id,
                                  d.data() as Map<String, dynamic>,
                                ),
                              )
                              .toList();

                          // Ordenamiento en memoria por fecha
                          listaTarifas.sort(
                            (a, b) => b.fechaDesde.compareTo(a.fechaDesde),
                          );

                          return ListView.separated(
                            itemCount: listaTarifas.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, i) {
                              final t = listaTarifas[i];
                              final bool esPromo = t.tipo == 'PROMOCION';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: esPromo
                                      ? Colors.amber.shade100
                                      : Colors.teal.shade50,
                                  child: Icon(
                                    esPromo
                                        ? Icons.star_rounded
                                        : Icons.price_change_rounded,
                                    color: esPromo
                                        ? Colors.amber.shade900
                                        : Colors.teal,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      '${t.deporte} - ${t.frecuencia}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (esPromo)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'PROMO ${t.duracionMeses} MESES',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Regular / Tarjeta: \$${t.precioRegular.toStringAsFixed(0)} | Efectivo: \$${t.precioEfectivo.toStringAsFixed(0)}'
                                  '${t.valorFinalTotal != null ? '\nValor Final Pack: \$${t.valorFinalTotal!.toStringAsFixed(0)}' : ''}'
                                  '${t.leyendaPromocion != null ? '\n${t.leyendaPromocion}' : ''}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => FirebaseFirestore.instance
                                      .collection('tarifas')
                                      .doc(t.id)
                                      .delete(),
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
            ),
          ],
        ),
      ),
    );
  }
}
