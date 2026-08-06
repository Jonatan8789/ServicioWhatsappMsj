import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CrearTorneoPage extends StatefulWidget {
  const CrearTorneoPage({super.key});

  @override
  State<CrearTorneoPage> createState() => _CrearTorneoPageState();
}

class _CrearTorneoPageState extends State<CrearTorneoPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _precioController = TextEditingController();

  String _categoriaSeleccionada = '5ta';
  String _ramaSeleccionada = 'Caballeros';
  int _maxParejas = 16;
  bool _cargando = false;

  final List<String> _categorias = [
    '1ra',
    '2da',
    '3ra',
    '4ta',
    '5ta',
    '6ta',
    '7ta',
    'Principiantes',
  ];
  final List<String> _ramas = ['Caballeros', 'Damas', 'Mixto'];
  final List<int> _cuposDisponibles = [8, 16, 32];

  Future<void> _guardarTorneo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    try {
      final double precio =
          double.tryParse(_precioController.text.trim()) ?? 0.0;

      await FirebaseFirestore.instance.collection('torneos').add({
        'nombre': _nombreController.text.trim(),
        'categoria': _categoriaSeleccionada,
        'rama': _ramaSeleccionada,
        'maxParejas': _maxParejas,
        'precioInscripcion': precio,
        'estado':
            'inscripcion_abierta', // inscripcion_abierta, en_curso, finalizado
        'parejas': [],
        'partidos': [],
        'fechaCreacion': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Torneo creado exitosamente!'),
            backgroundColor: Color(0xFF0A3B43),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear torneo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color oquaPrimary = Color(0xFF0A3B43);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Torneo de Pádel'),
        backgroundColor: oquaPrimary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
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
                  const Text(
                    'Paso A: Configuración del Torneo',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Nombre del Torneo
                  TextFormField(
                    controller: _nombreController,
                    decoration: InputDecoration(
                      labelText: 'Nombre del Torneo',
                      hintText: 'Ej: Torneo Aniversario OQUA',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Campo obligatorio' : null,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      // Categoría
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _categoriaSeleccionada,
                          decoration: InputDecoration(
                            labelText: 'Categoría',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: _categorias
                              .map(
                                (cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _categoriaSeleccionada = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Rama
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _ramaSeleccionada,
                          decoration: InputDecoration(
                            labelText: 'Rama',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: _ramas
                              .map(
                                (r) =>
                                    DropdownMenuItem(value: r, child: Text(r)),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _ramaSeleccionada = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      // Cupo Máximo de Parejas
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _maxParejas,
                          decoration: InputDecoration(
                            labelText: 'Cupo de Parejas',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: _cuposDisponibles
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text('$c Parejas'),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _maxParejas = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Precio por Pareja
                      Expanded(
                        child: TextFormField(
                          controller: _precioController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Precio por Pareja (\$)',
                            hintText: '15000',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          validator: (val) => val == null || val.isEmpty
                              ? 'Campo obligatorio'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  _cargando
                      ? const Center(
                          child: CircularProgressIndicator(color: oquaPrimary),
                        )
                      : ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: oquaPrimary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _guardarTorneo,
                          icon: const Icon(Icons.emoji_events),
                          label: const Text(
                            'Publicar Torneo',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
