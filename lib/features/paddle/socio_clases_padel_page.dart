import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../shared/mercado_pago_dialog.dart';
import 'clase_padel_model.dart';
import 'clase_padel_repository.dart';

class SocioClasesPadelPage extends StatefulWidget {
  const SocioClasesPadelPage({super.key});

  @override
  State<SocioClasesPadelPage> createState() => _SocioClasesPadelPageState();
}

class _SocioClasesPadelPageState extends State<SocioClasesPadelPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime _fechaSeleccionada = DateTime.now();
  Map<String, dynamic>? _datosSocio;
  String? _socioDocId;

  @override
  void initState() {
    super.initState();
    _cargarSocio();
  }

  Future<void> _cargarSocio() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // 🚨 El id del doc 'socios/{id}' no es el uid de Auth — buscar por
    // 'usuarioUid' (mismo criterio que el resto de las pantallas de socio).
    final query = await _firestore
        .collection('socios')
        .where('usuarioUid', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty && mounted) {
      setState(() {
        _socioDocId = query.docs.first.id;
        _datosSocio = query.docs.first.data();
      });
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _inscribirse(ClasePadelModel clase) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _socioDocId == null) {
      _snack(
        'No encontramos tu ficha de socio. Contactá a administración.',
        Colors.red,
      );
      return;
    }
    final String nombreSocio = _datosSocio != null
        ? '${_datosSocio!['nombre'] ?? ''} ${_datosSocio!['apellido'] ?? ''}'
              .trim()
        : 'Socio';

    try {
      final entroDirecto = await inscribirseAClasePadelAtomica(
        firestore: _firestore,
        claseId: clase.id,
        socioId: _socioDocId!,
        socioNombre: nombreSocio,
        ventaSocioId: user.uid,
      );
      _snack(
        entroDirecto
            ? '✅ ¡Anotado en ${clase.nombre}! Vas a ver el pago pendiente en "Mis pagos".'
            : '⏳ La clase está completa, quedaste en lista de espera (no se te cobra hasta que entres).',
        entroDirecto ? Colors.green : Colors.orange,
      );
    } on ClaseNoDisponibleException catch (e) {
      _snack('$e', Colors.red);
    } on YaInscriptoEnClasePadelException {
      _snack('Ya estás anotado en esa clase.', Colors.orange);
    } catch (e) {
      _snack('Error: $e', Colors.red);
    }
  }

  // 🚨 La cancelación pasa por una Cloud Function (no por el repositorio
  // directo): si al cancelar se promueve a alguien de la lista de espera,
  // esa promoción le crea una 'venta_pendiente' a ESA OTRA PERSONA, algo
  // que un socio no puede hacer directo desde el cliente (ver el aviso en
  // clase_padel_repository.dart / cancelarInscripcionClasePadelAtomica).
  Future<void> _cancelar(ClasePadelModel clase) async {
    try {
      final resp = await FirebaseFunctions.instance
          .httpsCallable('cancelarInscripcionClasePadelSocio')
          .call({'claseId': clase.id});
      if (resp.data['success'] == true) {
        _snack('Te diste de baja de ${clase.nombre}.', Colors.orange);
      } else {
        _snack(
          resp.data['error'] ?? 'No se pudo cancelar la inscripción.',
          Colors.red,
        );
      }
    } catch (e) {
      _snack('Error: $e', Colors.red);
    }
  }

  Widget _buildEstadoPago(ClasePadelModel clase, String socioDocId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore
          .collection('pagos_clases_padel')
          .doc('${clase.id}_$socioDocId')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final pago = PagoClasePadelModel.fromFirestore(
          snap.data!.id,
          snap.data!.data() as Map<String, dynamic>,
        );
        if (pago.estaPago) {
          return const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '✅ Pago al día',
              style: TextStyle(color: Colors.green, fontSize: 12),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '⏳ Pendiente: \$${pago.monto.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                label: const Text('Pagar con Mercado Pago'),
                onPressed: () => mostrarDialogoCobroMercadoPago(
                  context,
                  concepto: 'Clase de Pádel: ${clase.nombre}',
                  campoMonto: 'monto',
                  campoMedioPago: 'medioPago',
                  cloudFunction: 'crearCobroMercadoPagoSocio',
                  parametrosExtra: {
                    'tipo': 'clase_padel',
                    'pagoClaseId': pago.id,
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final socioDocId = _socioDocId;
    final inicioDia = DateTime(
      _fechaSeleccionada.year,
      _fechaSeleccionada.month,
      _fechaSeleccionada.day,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Clases de Pádel'),
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
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      setState(() => _fechaSeleccionada = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('clases_padel')
                  .where(
                    'fecha',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia),
                  )
                  .where(
                    'fecha',
                    isLessThan: Timestamp.fromDate(
                      inicioDia.add(const Duration(days: 1)),
                    ),
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final clases = snapshot.data!.docs
                    .map(
                      (d) => ClasePadelModel.fromFirestore(
                        d.id,
                        d.data() as Map<String, dynamic>,
                      ),
                    )
                    .where((c) => c.estadoClase == 'Programada')
                    .toList()
                  ..sort((a, b) => a.horaInicio.compareTo(b.horaInicio));

                if (clases.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay clases programadas este día.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: clases.length,
                  itemBuilder: (context, i) {
                    final c = clases[i];
                    final inscripto =
                        socioDocId != null &&
                        c.inscriptosIds.contains(socioDocId);
                    final enEspera =
                        socioDocId != null &&
                        c.listaEsperaIds.contains(socioDocId);
                    final lugares = c.cupoMaximo - c.inscriptosIds.length;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c.nombre} · ${c.horaInicio.toString().padLeft(2, '0')}:00 hs',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Profesor: ${c.profesorNombre} · Cancha: ${c.cancha}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            Text(
                              '\$${c.precioPorAlumno.toStringAsFixed(0)} por alumno',
                            ),
                            Text(
                              lugares > 0
                                  ? 'Lugares disponibles: $lugares/${c.cupoMaximo}'
                                  : 'Completo (${c.listaEsperaIds.length} en lista de espera)',
                            ),
                            if (inscripto)
                              _buildEstadoPago(c, socioDocId),
                            const SizedBox(height: 8),
                            if (inscripto || enEspera)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => _cancelar(c),
                                  child: Text(
                                    enEspera
                                        ? 'Salir de la lista de espera'
                                        : 'Cancelar mi lugar',
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => _inscribirse(c),
                                  child: Text(
                                    lugares > 0
                                        ? 'Inscribirme'
                                        : 'Anotarme en lista de espera',
                                  ),
                                ),
                              ),
                          ],
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
