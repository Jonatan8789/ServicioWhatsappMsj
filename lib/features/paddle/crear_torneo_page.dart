import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'torneo_categorias.dart';

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
  // 🚨 Antes el torneo no tenía formato: se creaba con 'parejas'/'partidos'
  // vacíos y sin ningún camino real para armar la llave. Ahora se define acá
  // el formato (y la cantidad de zonas si aplica), que después usa
  // TorneoFirestoreService para sortear.
  String _formatoSeleccionado = TorneoCategorias.formatos[0];
  int _cantidadGrupos = 4;
  bool _cargando = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _precioController.dispose();
    super.dispose();
  }

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
        'faseActual': 'inscripcion', // inscripcion, grupos, llave, finalizado
        'formatoElegido': _formatoSeleccionado,
        if (_formatoSeleccionado == TorneoCategorias.formatos[2])
          'cantidadGruposElegida': _cantidadGrupos,
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
                          initialValue: _categoriaSeleccionada,
                          decoration: InputDecoration(
                            labelText: 'Categoría',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: TorneoCategorias.lista
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
                          initialValue: _ramaSeleccionada,
                          decoration: InputDecoration(
                            labelText: 'Rama',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: TorneoCategorias.ramas
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
                          initialValue: _maxParejas,
                          decoration: InputDecoration(
                            labelText: 'Cupo de Parejas',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: TorneoCategorias.cuposDisponibles
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
                  const SizedBox(height: 24),

                  const Text(
                    'Paso B: Formato del Torneo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _formatoSeleccionado,
                    decoration: InputDecoration(
                      labelText: 'Formato',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: TorneoCategorias.formatos
                        .map(
                          (f) => DropdownMenuItem(value: f, child: Text(f)),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _formatoSeleccionado = val);
                      }
                    },
                  ),
                  if (_formatoSeleccionado == TorneoCategorias.formatos[2]) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _cantidadGrupos,
                      decoration: InputDecoration(
                        labelText: 'Cantidad de Zonas',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: [2, 4, 8]
                          .where((c) => _maxParejas >= c * 2)
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text('$c Zonas'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _cantidadGrupos = val);
                      },
                    ),
                  ],
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
