import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tarifa_model.dart';

class TarifasPage extends StatefulWidget {
  const TarifasPage({super.key});

  @override
  State<TarifasPage> createState() => _TarifasPageState();
}

class _TarifasPageState extends State<TarifasPage> {
  final _formKey = GlobalKey<FormState>();
  final _precioController = TextEditingController();

  List<String> _deportes = [];
  List<String> _frecuencias = [];

  // Constantes fijas para la duración del alquiler de canchas
  final List<String> _duracionesCancha = [
    '60 Minutos (1 Hora)',
    '90 Minutos (1.5 Horas)',
    '120 Minutos (2 Horas)',
  ];

  String? _deporteSel;
  String? _frecuenciaSel; // Se usará tanto para Frecuencia como para Duración
  bool _cargandoConstantes = true;

  @override
  void initState() {
    super.initState();
    _cargarConstantes();
  }

  @override
  void dispose() {
    _precioController.dispose();
    super.dispose();
  }

  Future<void> _cargarConstantes() async {
    try {
      final configRef = FirebaseFirestore.instance.collection('configuracion');
      final resultados = await Future.wait([
        configRef.doc('deportes').get(),
        configRef.doc('frecuencias').get(),
      ]);

      setState(() {
        if (resultados[0].exists) {
          _deportes = List<String>.from(resultados[0].data()?['lista'] ?? []);
        }
        // Nos aseguramos de agregar "Paddle (Alquiler Cancha)" a la lista si no existiera en Firestore
        if (!_deportes.contains('Paddle (Alquiler Cancha)')) {
          _deportes.add('Paddle (Alquiler Cancha)');
        }

        if (resultados[1].exists) {
          _frecuencias = List<String>.from(
            resultados[1].data()?['lista'] ?? [],
          );
        }
        _cargandoConstantes = false;
      });
    } catch (e) {
      setState(() => _cargandoConstantes = false);
    }
  }

  Future<void> _guardarTarifa() async {
    if (!_formKey.currentState!.validate() ||
        _deporteSel == null ||
        _frecuenciaSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, completa todos los campos.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final precio = double.tryParse(_precioController.text.trim()) ?? 0.0;
    final idDocumento = "${_deporteSel}_$_frecuenciaSel";

    final nuevaTarifa = TarifaModel(
      id: idDocumento,
      deporte: _deporteSel!,
      frecuencia:
          _frecuenciaSel!, // Almacena la frecuencia o la duración según corresponda
      precio: precio,
    );

    await FirebaseFirestore.instance
        .collection('tarifas')
        .doc(idDocumento)
        .set(nuevaTarifa.toFirestore());

    _precioController.clear();
    setState(() {
      _deporteSel = null;
      _frecuenciaSel = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('¡Tarifa/Alquiler guardado con éxito!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _eliminarTarifa(String id) async {
    await FirebaseFirestore.instance.collection('tarifas').doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoConstantes) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Flag inteligente para saber si estamos configurando cuotas de socios o alquileres
    final bool esAlquilerCancha = _deporteSel == 'Paddle (Alquiler Cancha)';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // COLUMNA IZQUIERDA: Formulario Dinámico
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Asignar Nueva Tarifa / Turno',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        esAlquilerCancha
                            ? 'Define el costo por bloque de tiempo para los turnos de las canchas de paddle.'
                            : 'Cruza una actividad con su frecuencia para definir el valor de la cuota mensual.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Selector de Actividad / Deporte
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Seleccionar Deporte o Recurso',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _deporteSel,
                        items: _deportes
                            .map(
                              (d) => DropdownMenuItem(value: d, child: Text(d)),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _deporteSel = val;
                            _frecuenciaSel =
                                null; // Limpiamos el segundo campo al cambiar de tipo
                          });
                        },
                      ),
                      const SizedBox(height: 20),

                      // Selector Secundario Inteligente (Frecuencia Semanal O Duración del Turno)
                      DropdownButtonFormField<String>(
                        key:
                            UniqueKey(), // Fuerza el redibujado correcto del componente
                        decoration: InputDecoration(
                          labelText: esAlquilerCancha
                              ? 'Duración del Turno de Alquiler'
                              : 'Seleccionar Frecuencia Semanal',
                          border: const OutlineInputBorder(),
                        ),
                        initialValue: _frecuenciaSel,
                        items:
                            (esAlquilerCancha
                                    ? _duracionesCancha
                                    : _frecuencias)
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(item),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) =>
                            setState(() => _frecuenciaSel = val),
                      ),
                      const SizedBox(height: 20),

                      // Monto de Dinero
                      TextFormField(
                        controller: _precioController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: esAlquilerCancha
                              ? 'Precio por Turno (\$)'
                              : 'Precio Cuota Mensual (\$)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.attach_money_rounded),
                        ),
                        validator: (v) =>
                            v!.isEmpty ? 'Ingresa un monto válido' : null,
                      ),
                      const SizedBox(height: 32),

                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(
                          esAlquilerCancha
                              ? Icons.sports_tennis_rounded
                              : Icons.add_card_rounded,
                        ),
                        label: Text(
                          esAlquilerCancha
                              ? 'Establecer Precio Alquiler'
                              : 'Establecer Precio Cuota',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _guardarTarifa,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),

            // COLUMNA DERECHA: Listado unificado en tiempo real
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Matriz de Precios y Alquileres Vigentes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 24),

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
                                'No hay tarifas ni precios de alquiler cargados aún.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, _) =>
                                const Divider(color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              final tarifa = TarifaModel.fromFirestore(
                                docs[index].id,
                                docs[index].data() as Map<String, dynamic>,
                              );
                              final bool esCancha =
                                  tarifa.deporte == 'Paddle (Alquiler Cancha)';

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor:
                                      (esCancha
                                              ? Colors.orange
                                              : Colors.blueAccent)
                                          .withValues(alpha: 0.1),
                                  child: Icon(
                                    esCancha
                                        ? Icons.sports_tennis_rounded
                                        : Icons.monetization_on_rounded,
                                    color: esCancha
                                        ? Colors.orange
                                        : Colors.blueAccent,
                                  ),
                                ),
                                title: Text(
                                  tarifa.deporte,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                subtitle: Text(
                                  esCancha
                                      ? "Módulo de Reserva: ${tarifa.frecuencia}"
                                      : "Asignación Cuota: ${tarifa.frecuencia}",
                                  style: const TextStyle(
                                    color: Colors.blueGrey,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '\$${tarifa.precio.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () =>
                                          _eliminarTarifa(tarifa.id),
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
          ],
        ),
      ),
    );
  }
}
