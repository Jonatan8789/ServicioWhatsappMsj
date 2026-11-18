import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../socios/socio_model.dart';
import 'andarivel_reserva_model.dart';
import 'andarivel_reserva_repository.dart';

class SocioReservaAndarivelPage extends StatefulWidget {
  const SocioReservaAndarivelPage({super.key});

  @override
  State<SocioReservaAndarivelPage> createState() =>
      _SocioReservaAndarivelPageState();
}

class _SocioReservaAndarivelPageState
    extends State<SocioReservaAndarivelPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _cargando = true;
  SocioModel? _socio;
  String _nombreSocio = 'Socio';

  List<String> _andarivelesActivos = [];
  int _horaApertura = 8;
  int _horaCierre = 21;
  Map<String, int> _cupoPorCategoria = {};

  DateTime _fechaSeleccionada = DateTime.now();
  late Stream<QuerySnapshot> _cuposDelDiaStream;

  @override
  void initState() {
    super.initState();
    _cuposDelDiaStream = _streamCuposDelDia(_fechaSeleccionada);
    _cargarTodo();
  }

  Stream<QuerySnapshot> _streamCuposDelDia(DateTime fecha) {
    final inicioDia = DateTime(fecha.year, fecha.month, fecha.day);
    return _firestore
        .collection('cupos_andariveles')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia))
        .where(
          'fecha',
          isLessThan: Timestamp.fromDate(inicioDia.add(const Duration(days: 1))),
        )
        .snapshots();
  }

  Future<void> _cargarTodo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docSocio = await _firestore
            .collection('socios')
            .doc(user.uid)
            .get();
        if (docSocio.exists) {
          _socio = SocioModel.fromFirestore(docSocio);
          _nombreSocio = _socio!.nombre;
        }
      }

      final docAndariveles = await _firestore
          .collection('configuracion_natatorio')
          .doc('andariveles')
          .get();
      _andarivelesActivos = (docAndariveles.exists &&
              docAndariveles.data()?['lista'] != null)
          ? List<String>.from(docAndariveles.data()!['lista'])
          : ['Andarivel 1', 'Andarivel 2', 'Andarivel 3', 'Andarivel 4'];

      final docAjustes = await _firestore
          .collection('configuracion_natatorio')
          .doc('ajustes_globales')
          .get();
      if (docAjustes.exists && docAjustes.data() != null) {
        final d = docAjustes.data()!;
        _horaApertura = (d['horaApertura'] as num?)?.toInt() ?? 8;
        _horaCierre = (d['horaCierre'] as num?)?.toInt() ?? 21;
        _cupoPorCategoria = d['cupoPorCategoria'] is Map
            ? Map<String, int>.from(
                (d['cupoPorCategoria'] as Map).map(
                  (k, v) => MapEntry(k.toString(), (v as num).toInt()),
                ),
              )
            : {'Libre': 6, 'Escuela': 12, 'Rehabilitación': 4};
      } else {
        _cupoPorCategoria = {'Libre': 6, 'Escuela': 12, 'Rehabilitación': 4};
      }
    } catch (e) {
      _snack('Error al cargar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _fechaIdStr(DateTime f) => "${f.year}-${f.month}-${f.day}";

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 🏊 Semáforo sanitario: sin Apto Médico o revisión de
    // pediculosis/micosis vigentes, no se puede reservar andarivel.
    if (_socio == null || !semaforoSanitarioNatatorioOk(_socio!)) {
      final aptoOk = _socio != null &&
          vencimientoVigente(_socio!.vencimientoAptoMedico);
      final sanitarioOk = _socio != null &&
          vencimientoVigente(_socio!.vencimientoPediculosisMicosis);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reservar Andarivel'),
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.health_and_safety_rounded,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No podés reservar un andarivel todavía',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (!aptoOk)
                  const Text(
                    '• Tu Apto Médico está vencido o no está cargado.',
                    textAlign: TextAlign.center,
                  ),
                if (!sanitarioOk)
                  const Text(
                    '• Tu revisión de pediculosis/micosis está vencida o no está cargada.',
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Acercate a recepción para regularizarlo.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Reservar Andarivel'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fecha: ${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Cambiar'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fechaSeleccionada,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 14)),
                    );
                    if (picked != null) {
                      setState(() {
                        _fechaSeleccionada = picked;
                        _cuposDelDiaStream = _streamCuposDelDia(picked);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _cuposDelDiaStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final Map<String, Map<String, dynamic>> cuposPorSlot = {
                  for (var doc in snapshot.data!.docs)
                    doc.id: doc.data() as Map<String, dynamic>,
                };

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _andarivelesActivos.map((andarivel) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              andarivel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(
                                _horaCierre - _horaApertura,
                                (i) {
                                  final hora = _horaApertura + i;
                                  final andarivelLimpio = andarivel
                                      .replaceAll(' ', '');
                                  final slotId =
                                      '${_fechaIdStr(_fechaSeleccionada)}_${andarivelLimpio}_${hora}hs';
                                  final cupoData = cuposPorSlot[slotId];
                                  final int ocupados =
                                      (cupoData?['ocupados'] as num?)
                                          ?.toInt() ??
                                      0;
                                  final String? categoria =
                                      cupoData?['categoria']?.toString();
                                  final int cupoMaximo = categoria != null
                                      ? (_cupoPorCategoria[categoria] ?? 0)
                                      : 0;
                                  final bool lleno =
                                      categoria != null &&
                                      ocupados >= cupoMaximo;

                                  return InkWell(
                                    onTap: lleno
                                        ? null
                                        : () => _reservar(andarivel, hora,
                                            categoria),
                                    child: Container(
                                      width: 110,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: lleno
                                            ? Colors.red.shade100
                                            : (categoria == null
                                                  ? Colors.green.shade50
                                                  : Colors.blue.shade50),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: lleno
                                              ? Colors.red.shade300
                                              : (categoria == null
                                                    ? Colors.green.shade300
                                                    : Colors.blue.shade300),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            '${hora.toString().padLeft(2, '0')}:00 hs',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            categoria == null
                                                ? 'Elegir categoría'
                                                : (lleno
                                                      ? '$categoria · Completo'
                                                      : '$categoria · $ocupados/$cupoMaximo'),
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reservar(
    String andarivel,
    int hora,
    String? categoriaActual,
  ) async {
    String categoriaElegida = categoriaActual ?? _cupoPorCategoria.keys.first;

    if (categoriaActual == null) {
      final elegida = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('¿En qué categoría vas a nadar?'),
          children: _cupoPorCategoria.keys
              .map(
                (c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text(c),
                ),
              )
              .toList(),
        ),
      );
      if (elegida == null) return;
      categoriaElegida = elegida;
    }

    final cupoMaximo = _cupoPorCategoria[categoriaElegida] ?? 0;

    final reserva = AndarivelReservaModel(
      id: 'sin-usar',
      andarivel: andarivel,
      categoria: categoriaElegida,
      nombreCliente: _nombreSocio,
      socioId: _socio?.id,
      fecha: _fechaSeleccionada,
      horaInicio: hora,
    );

    try {
      await reservarAndariveloAtomica(
        firestore: _firestore,
        reserva: reserva,
        cupoMaximo: cupoMaximo,
      );
      _snack('🏊 Turno reservado correctamente.', Colors.green);
    } on CupoLlenoException {
      _snack('Ese turno ya está completo.', Colors.red);
    } on YaAnotadoException {
      _snack('Ya estás anotado en ese turno.', Colors.orange);
    } on CategoriaDelTurnoException {
      _snack('Ese turno ya quedó fijado con otra categoría.', Colors.red);
    } catch (e) {
      _snack('Error al reservar: $e', Colors.red);
    }
  }
}
