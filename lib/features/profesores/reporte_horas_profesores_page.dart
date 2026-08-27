import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../profesores/profesor_model.dart';
import '../asistencias/asistencia_model.dart';

class ReporteHorasProfesoresPage extends StatefulWidget {
  const ReporteHorasProfesoresPage({super.key});

  @override
  State<ReporteHorasProfesoresPage> createState() =>
      _ReporteHorasProfesoresPageState();
}

class _ReporteHorasProfesoresPageState
    extends State<ReporteHorasProfesoresPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _rangoSeleccionado = 'Mensual'; // 'Semanal', 'Quincenal', 'Mensual', 'Personalizado'
  DateTime _fechaDesde = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _fechaHasta = DateTime.now();
  String? _profesorFiltroId;

  @override
  void initState() {
    super.initState();
    _actualizarRangoFechas('Mensual');
  }

  void _actualizarRangoFechas(String opcion) {
    final hoy = DateTime.now();
    setState(() {
      _rangoSeleccionado = opcion;
      if (opcion == 'Semanal') {
        _fechaDesde = hoy.subtract(Duration(days: hoy.weekday - 1));
        _fechaHasta = hoy;
      } else if (opcion == 'Quincenal') {
        if (hoy.day <= 15) {
          _fechaDesde = DateTime(hoy.year, hoy.month, 1);
          _fechaHasta = DateTime(hoy.year, hoy.month, 15);
        } else {
          _fechaDesde = DateTime(hoy.year, hoy.month, 16);
          _fechaHasta = DateTime(hoy.year, hoy.month + 1, 0);
        }
      } else if (opcion == 'Mensual') {
        _fechaDesde = DateTime(hoy.year, hoy.month, 1);
        _fechaHasta = DateTime(hoy.year, hoy.month + 1, 0);
      }
    });
  }

  // ⏱️ CÁLCULO DE MINUTOS/HORAS ENTRE ENTRADA Y SALIDA
  double _calcularHorasEntre(AsistenciaModel entrada, AsistenciaModel? salida) {
    if (salida == null) return 0.0;
    final diferencia = salida.fecha.difference(entrada.fecha);
    return diferencia.inMinutes / 60.0;
  }

  // ➕ DIÁLOGO PARA ASENTAR FICHADA MANUL DE CORRECCIÓN (ADMIN)
  void _mostrarDialogoAjusteManual(List<ProfesorModel> profesores) {
    String? profeSelId;
    String? profeSelNombre;
    DateTime fechaFichada = DateTime.now();
    TimeOfDay horaEntrada = const TimeOfDay(hour: 08, minute: 0);
    TimeOfDay horaSalida = const TimeOfDay(hour: 12, minute: 0);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_calendar_rounded, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Ajuste Manual de Horas'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Profesor',
                    border: OutlineInputBorder(),
                  ),
                  items: profesores
                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombre)))
                      .toList(),
                  onChanged: (val) {
                    final p = profesores.firstWhere((element) => element.id == val);
                    setModalState(() {
                      profeSelId = p.id;
                      profeSelNombre = p.nombre;
                    });
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Fecha de Fichada:'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(fechaFichada)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final f = await showDatePicker(
                      context: context,
                      initialDate: fechaFichada,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (f != null) setModalState(() => fechaFichada = f);
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        title: const Text('Entrada:'),
                        subtitle: Text(horaEntrada.format(context)),
                        onTap: () async {
                          final h = await showTimePicker(
                            context: context,
                            initialTime: horaEntrada,
                          );
                          if (h != null) setModalState(() => horaEntrada = h);
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        title: const Text('Salida:'),
                        subtitle: Text(horaSalida.format(context)),
                        onTap: () async {
                          final h = await showTimePicker(
                            context: context,
                            initialTime: horaSalida,
                          );
                          if (h != null) setModalState(() => horaSalida = h);
                        },
                      ),
                    ),
                  ],
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: profeSelId == null
                  ? null
                  : () async {
                      final dtEntrada = DateTime(
                        fechaFichada.year,
                        fechaFichada.month,
                        fechaFichada.day,
                        horaEntrada.hour,
                        horaEntrada.minute,
                      );
                      final dtSalida = DateTime(
                        fechaFichada.year,
                        fechaFichada.month,
                        fechaFichada.day,
                        horaSalida.hour,
                        horaSalida.minute,
                      );

                      final hoyStr =
                          "${fechaFichada.year}-${fechaFichada.month.toString().padLeft(2, '0')}-${fechaFichada.day.toString().padLeft(2, '0')}";

                      // Batch para guardar Entrada y Salida
                      WriteBatch batch = _firestore.batch();

                      DocumentReference refEntrada = _firestore
                          .collection('asistencia')
                          .doc("${hoyStr}_${profeSelId}_Entrada_MANUAL");

                      batch.set(refEntrada, {
                        'profesorId': profeSelId,
                        'nombreProfesor': profeSelNombre,
                        'fecha': Timestamp.fromDate(dtEntrada),
                        'tipo': 'Entrada',
                        'hora':
                            "${horaEntrada.hour.toString().padLeft(2, '0')}:${horaEntrada.minute.toString().padLeft(2, '0')}",
                        'observacion': 'Ajuste Manual por Administración',
                      });

                      DocumentReference refSalida = _firestore
                          .collection('asistencia')
                          .doc("${hoyStr}_${profeSelId}_Salida_MANUAL");

                      batch.set(refSalida, {
                        'profesorId': profeSelId,
                        'nombreProfesor': profeSelNombre,
                        'fecha': Timestamp.fromDate(dtSalida),
                        'tipo': 'Salida',
                        'hora':
                            "${horaSalida.hour.toString().padLeft(2, '0')}:${horaSalida.minute.toString().padLeft(2, '0')}",
                        'observacion': 'Ajuste Manual por Administración',
                      });

                      await batch.commit();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Asistencia cargada manualmente.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
              child: const Text('Cargar Fichada', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime inicioFiltro =
        DateTime(_fechaDesde.year, _fechaDesde.month, _fechaDesde.day, 0, 0, 0);
    final DateTime finFiltro =
        DateTime(_fechaHasta.year, _fechaHasta.month, _fechaHasta.day, 23, 59, 59);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CABECERA Y BOTONERA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reporte y Liquidación de Horas Docentes',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Consolidado de asistencia y horas calculadas por docente.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('profesores').snapshots(),
                  builder: (context, snapProfes) {
                    List<ProfesorModel> listaProfes = [];
                    if (snapProfes.hasData) {
                      listaProfes = snapProfes.data!.docs
                          .map((d) => ProfesorModel.fromFirestore(
                              d.id, d.data() as Map<String, dynamic>))
                          .toList();
                    }

                    return ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                      ),
                      onPressed: () => _mostrarDialogoAjusteManual(listaProfes),
                      icon: const Icon(Icons.access_time_rounded, color: Colors.white),
                      label: const Text(
                        'Ajustar Fichada Manual',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // BARRA DE FILTROS TEMPORALES
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Text('Rango Rápido: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Semanal', 'Quincenal', 'Mensual'].map((opcion) {
                      final sel = _rangoSeleccionado == opcion;
                      return ChoiceChip(
                        label: Text(opcion),
                        selected: sel,
                        selectedColor: Colors.teal.shade100,
                        onSelected: (_) => _actualizarRangoFechas(opcion),
                      );
                    }).toList(),
                  ),
                  const Spacer(),
                  const Icon(Icons.date_range, color: Colors.teal),
                  const SizedBox(width: 8),
                  Text(
                    '${DateFormat('dd/MM/yyyy').format(_fechaDesde)} al ${DateFormat('dd/MM/yyyy').format(_fechaHasta)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // LISTADO Y CÁLCULO EN TIEMPO REAL
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('asistencia')
                    .where('fecha', isGreaterThanOrEqualTo: inicioFiltro)
                    .where('fecha', isLessThanOrEqualTo: finFiltro)
                    .orderBy('fecha', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No hay marcas de fichaje registradas en el período seleccionado.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  // Mapear asistencias y agrupar por Profesor
                  final Map<String, List<AsistenciaModel>> mapFichadasProfe = {};
                  for (var doc in docs) {
                    final asist = AsistenciaModel.fromFirestore(
                      doc.id,
                      doc.data() as Map<String, dynamic>,
                    );
                    mapFichadasProfe.putIfAbsent(asist.profesorId, () => []);
                    mapFichadasProfe[asist.profesorId]!.add(asist);
                  }

                  return ListView.builder(
                    itemCount: mapFichadasProfe.keys.length,
                    itemBuilder: (context, index) {
                      final profeId = mapFichadasProfe.keys.elementAt(index);
                      final fichadas = mapFichadasProfe[profeId]!;
                      final String nombreProfe =
                          fichadas.first.nombreProfesor.isEmpty
                              ? 'Profesor ID: $profeId'
                              : fichadas.first.nombreProfesor;

                      double totalHorasProfe = 0.0;
                      List<Widget> filasDetalle = [];

                      // Procesar pares Entrada / Salida
                      for (int i = 0; i < fichadas.length; i++) {
                        final item = fichadas[i];
                        if (item.tipo == 'Entrada') {
                          AsistenciaModel? salidaCorrespondiente;

                          // Buscar la salida siguiente
                          if (i + 1 < fichadas.length &&
                              fichadas[i + 1].tipo == 'Salida') {
                            salidaCorrespondiente = fichadas[i + 1];
                          }

                          final double hs = _calcularHorasEntre(
                              item, salidaCorrespondiente);
                          totalHorasProfe += hs;

                          filasDetalle.add(
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '📅 ${DateFormat('dd/MM/yyyy').format(item.fecha)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text('Entrada: ${item.hora}'),
                                  Text(
                                    salidaCorrespondiente != null
                                        ? 'Salida: ${salidaCorrespondiente.hora}'
                                        : '⚠️ SIN SALIDA',
                                    style: TextStyle(
                                      color: salidaCorrespondiente != null
                                          ? Colors.black87
                                          : Colors.red,
                                      fontWeight: salidaCorrespondiente == null
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  Text(
                                    '${hs.toStringAsFixed(2)} hs',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal.shade50,
                            child: const Icon(Icons.badge, color: Colors.teal),
                          ),
                          title: Text(
                            nombreProfe,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            'Entradas registradas: ${fichadas.where((f) => f.tipo == 'Entrada').length}',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade700,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'TOTAL: ${totalHorasProfe.toStringAsFixed(2)} HS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(),
                                  const Text(
                                    'Desglose de Fichadas:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(height: 8),
                                  ...filasDetalle,
                                ],
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
    );
  }
}