import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class LiquidacionesProfesoresPage extends StatefulWidget {
  const LiquidacionesProfesoresPage({super.key});

  @override
  State<LiquidacionesProfesoresPage> createState() =>
      _LiquidacionesProfesoresPageState();
}

class _LiquidacionesProfesoresPageState
    extends State<LiquidacionesProfesoresPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _profesorFiltroId;

  // 📝 DIÁLOGO PARA REGISTRAR/ACTUALIZAR ESQUEMA DE TARIFAS CON ACTIVIDADES CONFIGURADAS
  void _mostrarDialogoConfiguracionTarifa({
    String? profesorId,
    String? profesorNombre,
    String? actividadActual,
    double? montoActual,
  }) async {
    List<String> actividadesDisponibles = ['Guardavidas', 'Natatorio', 'Pádel'];

    try {
      final docDeportes = await _firestore
          .collection('configuracion')
          .doc('deportes')
          .get();
      if (docDeportes.exists && docDeportes.data() != null) {
        final List<dynamic> listaRaw = docDeportes.data()!['lista'] ?? [];
        if (listaRaw.isNotEmpty) {
          actividadesDisponibles = List<String>.from(listaRaw);
        }
      }
    } catch (_) {}

    if (!actividadesDisponibles.contains('Guardavidas')) {
      actividadesDisponibles.insert(0, 'Guardavidas');
    }

    String actividadSeleccionada =
        (actividadActual != null &&
            actividadesDisponibles.contains(actividadActual))
        ? actividadActual
        : actividadesDisponibles.first;

    final valorHoraCtrl = TextEditingController(
      text: montoActual != null ? montoActual.toStringAsFixed(0) : '8000',
    );
    DateTime fechaVigencia = DateTime.now();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.history_edu, color: Color(0xFF0F172A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  profesorId == null
                      ? 'Nueva Tarifa General por Actividad'
                      : 'Nueva Tarifa para $profesorNombre',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: actividadSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Actividad / Función',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.sports_rounded),
                  ),
                  items: actividadesDisponibles
                      .map(
                        (act) => DropdownMenuItem(value: act, child: Text(act)),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() => actividadSeleccionada = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valorHoraCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor Hora (\$ ARS)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Inicio de Vigencia de la Tarifa'),
                  subtitle: Text(
                    DateFormat('dd/MM/yyyy').format(fechaVigencia),
                  ),
                  trailing: const Icon(Icons.calendar_month),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fechaVigencia,
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setModalState(() => fechaVigencia = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
              ),
              onPressed: () async {
                final double nuevoMonto =
                    double.tryParse(valorHoraCtrl.text) ?? 0.0;

                if (nuevoMonto <= 0) return;

                await _firestore.collection('tarifas_honorarios_profes').add({
                  'profesorId': profesorId ?? 'GENERAL',
                  'profesorNombre': profesorNombre ?? 'Tarifa Base General',
                  'actividad': actividadSeleccionada,
                  'valorHora': nuevoMonto,
                  'fechaInicioVigencia': Timestamp.fromDate(fechaVigencia),
                  'fechaRegistro': DateTime.now(),
                });

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '✅ Esquema tarifario asentado en histórico.',
                      ),
                      backgroundColor: Colors.teal,
                    ),
                  );
                }
              },
              child: const Text(
                'Guardar Vigencia',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔍 BUSCADOR DE TARIFA CORRESPONDIENTE SEGÚN LA FECHA DE LA HORA TRABAJADA
  double _obtenerTarifaVigenteParaHora({
    required List<DocumentSnapshot> listaTarifas,
    required String profesorId,
    required String actividad,
    required DateTime fechaHoraTrabajada,
  }) {
    double tarifaCalculada = 0.0;
    DateTime? ultimaFechaCoincidente;

    for (var doc in listaTarifas) {
      final data = doc.data() as Map<String, dynamic>;
      final String pId = data['profesorId'] ?? 'GENERAL';
      final String act = data['actividad'] ?? '';
      final double monto = (data['valorHora'] as num?)?.toDouble() ?? 0.0;
      final DateTime vigencia = (data['fechaInicioVigencia'] as Timestamp)
          .toDate();

      bool esEspecificoProfe = (pId == profesorId);
      bool esGeneral = (pId == 'GENERAL');

      if ((esEspecificoProfe || esGeneral) &&
          act.toLowerCase() == actividad.toLowerCase() &&
          !fechaHoraTrabajada.isBefore(vigencia)) {
        if (ultimaFechaCoincidente == null ||
            vigencia.isAfter(ultimaFechaCoincidente)) {
          ultimaFechaCoincidente = vigencia;
          tarifaCalculada = monto;
        }
      }
    }

    return tarifaCalculada;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Liquidación de Profesores & Cuadro Tarifario'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_chart_rounded),
            tooltip: 'Añadir Nueva Vigencia de Tarifa',
            onPressed: () => _mostrarDialogoConfiguracionTarifa(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📊 SECCIÓN IZQUIERDA: HISTÓRICO EN PANTALLA DE TARIFAS POR ACTIVIDAD
            Expanded(
              flex: 2,
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Histórico de Tarifas & Vigencias',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade800,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Asignar Tarifa'),
                            onPressed: () =>
                                _mostrarDialogoConfiguracionTarifa(),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('tarifas_honorarios_profes')
                              .orderBy('fechaInicioVigencia', descending: true)
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
                                  'Sin tarifas registradas. Creá una tarifa por actividad.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              );
                            }

                            return ListView.builder(
                              itemCount: docs.length,
                              itemBuilder: (context, i) {
                                final data =
                                    docs[i].data() as Map<String, dynamic>;
                                final DateTime vigencia =
                                    (data['fechaInicioVigencia'] as Timestamp)
                                        .toDate();
                                final double valor =
                                    (data['valorHora'] as num?)?.toDouble() ??
                                    0.0;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${data['actividad']} (${data['profesorNombre']})',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'Vigencia desde: ${DateFormat('dd/MM/yyyy').format(vigencia)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '\$${valor.toStringAsFixed(2)} / hora',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ],
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
            ),
            const SizedBox(width: 24),

            // 💰 SECCIÓN DERECHA: CONSOLIDADO DE HORAS A LIQUIDAR
            Expanded(
              flex: 3,
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('tarifas_honorarios_profes')
                    .snapshots(),
                builder: (context, snapTarifas) {
                  if (!snapTarifas.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final listaTarifas = snapTarifas.data!.docs;

                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('profesores').snapshots(),
                    builder: (context, snapProfes) {
                      if (!snapProfes.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final profes = snapProfes.data!.docs;

                      return ListView.builder(
                        itemCount: profes.length,
                        itemBuilder: (context, idx) {
                          final pData =
                              profes[idx].data() as Map<String, dynamic>;
                          final String pId = profes[idx].id;
                          final String pNombre = pData['nombre'] ?? 'Profesor';

                          return StreamBuilder<QuerySnapshot>(
                            stream: _firestore
                                .collection('registro_horas_profes')
                                .where('profesorId', isEqualTo: pId)
                                .where('liquidado', isEqualTo: false)
                                .snapshots(),
                            builder: (context, snapHoras) {
                              Map<String, double> totalHorasPorActividad = {};
                              Map<String, double> totalMontoPorActividad = {};
                              double acumuladoGeneralARS = 0.0;

                              if (snapHoras.hasData) {
                                for (var hDoc in snapHoras.data!.docs) {
                                  final hData =
                                      hDoc.data() as Map<String, dynamic>;
                                  final double cantHoras =
                                      (hData['cantidadHoras'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                                  final String actividad =
                                      hData['actividad'] ??
                                      hData['funcion'] ??
                                      'Natatorio';
                                  final DateTime fechaHora =
                                      (hData['fecha'] as Timestamp).toDate();

                                  final double tarifaAplicable =
                                      _obtenerTarifaVigenteParaHora(
                                        listaTarifas: listaTarifas,
                                        profesorId: pId,
                                        actividad: actividad,
                                        fechaHoraTrabajada: fechaHora,
                                      );

                                  final double subtotalARS =
                                      cantHoras * tarifaAplicable;

                                  totalHorasPorActividad[actividad] =
                                      (totalHorasPorActividad[actividad] ?? 0) +
                                      cantHoras;
                                  totalMontoPorActividad[actividad] =
                                      (totalMontoPorActividad[actividad] ?? 0) +
                                      subtotalARS;
                                  acumuladoGeneralARS += subtotalARS;
                                }
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ExpansionTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFF0F172A),
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(
                                    pNombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Actividades pendientes: ${totalHorasPorActividad.length}',
                                    style: const TextStyle(
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '\$${acumuladoGeneralARS.toStringAsFixed(2)} ARS',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green,
                                        ),
                                      ),
                                      const Text(
                                        'A Liquidar',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ...totalHorasPorActividad.entries.map((
                                            entry,
                                          ) {
                                            final act = entry.key;
                                            final horas = entry.value;
                                            final monto =
                                                totalMontoPorActividad[act] ??
                                                0.0;

                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 4.0,
                                                  ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    '• $act: ${horas.toStringAsFixed(1)} hs',
                                                  ),
                                                  Text(
                                                    '\$${monto.toStringAsFixed(2)} ARS',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                          const Divider(height: 20),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              OutlinedButton.icon(
                                                icon: const Icon(
                                                  Icons.add,
                                                  size: 16,
                                                ),
                                                label: const Text(
                                                  'Tarifa Específica',
                                                ),
                                                onPressed: () =>
                                                    _mostrarDialogoConfiguracionTarifa(
                                                      profesorId: pId,
                                                      profesorNombre: pNombre,
                                                    ),
                                              ),
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.green.shade800,
                                                ),
                                                icon: const Icon(
                                                  Icons.check_circle_outline,
                                                  color: Colors.white,
                                                ),
                                                label: const Text(
                                                  'Cerrar y Emitir Liquidación',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                onPressed:
                                                    acumuladoGeneralARS <= 0
                                                    ? null
                                                    : () async {
                                                        final batch = _firestore
                                                            .batch();
                                                        for (var doc
                                                            in snapHoras
                                                                .data!
                                                                .docs) {
                                                          batch.update(
                                                            doc.reference,
                                                            {
                                                              'liquidado': true,
                                                              'fechaLiquidacion':
                                                                  DateTime.now(),
                                                            },
                                                          );
                                                        }
                                                        await batch.commit();

                                                        if (mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                '✅ Liquidación registrada para $pNombre',
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
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
}
