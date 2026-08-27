import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SocioReservaPaddlePage extends StatefulWidget {
  final String socioId;
  final String socioNombre;

  const SocioReservaPaddlePage({
    super.key,
    required this.socioId,
    required this.socioNombre,
  });

  @override
  State<SocioReservaPaddlePage> createState() => _SocioReservaPaddlePageState();
}

class _SocioReservaPaddlePageState extends State<SocioReservaPaddlePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime _fechaSeleccionada = DateTime.now();
  String? _canchaSeleccionada;
  int? _horaInicioSeleccionada;
  bool _alquilaPaleta = false;
  bool _alquilaPelotas = false;

  // Parámetros por defecto
  double _precioBase = 4500.0;
  int _horaApertura = 8;
  int _horaCierre = 23;

  Future<void> _confirmarReservaSocio() async {
    if (_canchaSeleccionada == null || _horaInicioSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecciona una cancha y un horario.'),
        ),
      );
      return;
    }

    final fechaIdStr =
        "${_fechaSeleccionada.year}-${_fechaSeleccionada.month}-${_fechaSeleccionada.day}";
    final reservaId =
        "${fechaIdStr}_${_canchaSeleccionada!.replaceAll(' ', '')}_${_horaInicioSeleccionada}hs_socioApp";

    try {
      await _firestore.collection('reservas_canchas').doc(reservaId).set({
        'id': reservaId,
        'cancha': _canchaSeleccionada,
        'nombreCliente': widget.socioNombre,
        'socioId': widget.socioId,
        'fecha': Timestamp.fromDate(_fechaSeleccionada),
        'horaInicio': _horaInicioSeleccionada,
        'duracionHoras': 1,
        'precio':
            _precioBase +
            (_alquilaPaleta ? 1500 : 0) +
            (_alquilaPelotas ? 1000 : 0),
        'metodoPago': 'Cuenta Corriente',
        'origen': 'Portal Socio',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎾 Turno reservado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reservar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaIdStr =
        "${_fechaSeleccionada.year}-${_fechaSeleccionada.month}-${_fechaSeleccionada.day}";

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Reservar Cancha de Pádel'),
        backgroundColor: const Color(0xFF0A3B43),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SELECCIÓN DE FECHA
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.calendar_month,
                  color: Color(0xFF0A3B43),
                ),
                title: Text(
                  'Fecha: ${DateFormat('dd/MM/yyyy').format(_fechaSeleccionada)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _fechaSeleccionada,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 15)),
                  );
                  if (picked != null)
                    setState(() => _fechaSeleccionada = picked);
                },
              ),
            ),
            const SizedBox(height: 20),

            // DETALLE DE LA SELECCIÓN
            if (_canchaSeleccionada != null && _horaInicioSeleccionada != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _canchaSeleccionada!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Horario: ${_horaInicioSeleccionada!.toString().padLeft(2, '0')}:00 hs',
                          style: const TextStyle(color: Colors.blueGrey),
                        ),
                      ],
                    ),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.teal,
                      size: 28,
                    ),
                  ],
                ),
              ),

            const Text(
              'Disponibilidad de Canchas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // GRILLA DE HORARIOS DINÁMICA
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('reservas_canchas').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                // Mapear reservas activas
                final reservasMap = <String, bool>{};
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final DateTime fechaRes = (data['fecha'] as Timestamp)
                      .toDate();
                  final String fId =
                      "${fechaRes.year}-${fechaRes.month}-${fechaRes.day}";
                  if (fId == fechaIdStr) {
                    final String cancha = data['cancha'] ?? '';
                    final int hInicio = data['horaInicio'] ?? 0;
                    final int duracion = data['duracionHoras'] ?? 1;
                    for (int i = 0; i < duracion; i++) {
                      reservasMap["${cancha}_${hInicio + i}"] = true;
                    }
                  }
                }

                final canchas = [
                  'Cancha 1 Cristal',
                  'Cancha 2 Cristal',
                  'Cancha 3 Muro',
                ];

                return Column(
                  children: canchas.map((cancha) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ExpansionTile(
                        initiallyExpanded: true,
                        title: Text(
                          cancha,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(
                                _horaCierre - _horaApertura,
                                (index) {
                                  final hora = _horaApertura + index;
                                  final bool ocupado =
                                      reservasMap["${cancha}_$hora"] ?? false;
                                  final bool seleccionado =
                                      _canchaSeleccionada == cancha &&
                                      _horaInicioSeleccionada == hora;

                                  return InkWell(
                                    onTap: ocupado
                                        ? null
                                        : () {
                                            setState(() {
                                              _canchaSeleccionada = cancha;
                                              _horaInicioSeleccionada = hora;
                                            });
                                          },
                                    child: Container(
                                      width: 100,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: ocupado
                                            ? Colors.red.shade50
                                            : (seleccionado
                                                  ? const Color(0xFF0A3B43)
                                                  : Colors.green.shade50),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: ocupado
                                              ? Colors.red.shade200
                                              : (seleccionado
                                                    ? const Color(0xFF0A3B43)
                                                    : Colors.green.shade300),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            "${hora.toString().padLeft(2, '0')}:00 hs",
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: ocupado
                                                  ? Colors.red.shade800
                                                  : (seleccionado
                                                        ? Colors.white
                                                        : Colors
                                                              .green
                                                              .shade900),
                                            ),
                                          ),
                                          Text(
                                            ocupado ? 'Ocupado' : 'Disponible',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: ocupado
                                                  ? Colors.red.shade600
                                                  : (seleccionado
                                                        ? Colors.white70
                                                        : Colors
                                                              .green
                                                              .shade700),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text('Alquiler de Paleta'),
              value: _alquilaPaleta,
              onChanged: (val) => setState(() => _alquilaPaleta = val ?? false),
            ),
            CheckboxListTile(
              title: const Text('Alquiler Tubo de Pelotas'),
              value: _alquilaPelotas,
              onChanged: (val) =>
                  setState(() => _alquilaPelotas = val ?? false),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A3B43),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _confirmarReservaSocio,
              child: const Text(
                'Confirmar Reserva',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
