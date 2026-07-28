import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ConfiguracionPaddlePage extends StatefulWidget {
  const ConfiguracionPaddlePage({super.key});

  @override
  State<ConfiguracionPaddlePage> createState() =>
      _ConfiguracionPaddlePageState();
}

class _ConfiguracionPaddlePageState extends State<ConfiguracionPaddlePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto para los valores de referencia del Club
  final _precioBaseCtrl = TextEditingController();
  final _precioLuzCtrl = TextEditingController();
  final _horaLuzCtrl = TextEditingController();
  final _precioPaletaCtrl = TextEditingController();

  // Controlador para dar de alta nuevas canchas
  final _nuevaCanchaCtrl = TextEditingController();

  bool _cargandoDatos = true;
  bool _guardando = false;
  List<String> _canchasExistentes = [];

  @override
  void initState() {
    super.initState();
    _cargarAjustesYCcanchas();
  }

  @override
  void dispose() {
    _precioBaseCtrl.dispose();
    _precioLuzCtrl.dispose();
    _horaLuzCtrl.dispose();
    _precioPaletaCtrl.dispose();
    _nuevaCanchaCtrl.dispose();
    super.dispose();
  }

  /// Recupera tanto la matriz de precios como el listado estructural de canchas
  Future<void> _cargarAjustesYCcanchas() async {
    try {
      // 1. Cargar Tarifas Globales
      final docAjustes = await _firestore
          .collection('configuraciones_paddle')
          .doc('ajustes_globales')
          .get();
      if (docAjustes.exists && docAjustes.data() != null) {
        final datos = docAjustes.data()!;
        _precioBaseCtrl.text = (datos['precio_base_cancha'] ?? '0').toString();
        _precioLuzCtrl.text = (datos['precio_adicional_luz'] ?? '0').toString();
        _horaLuzCtrl.text = (datos['hora_inicio_luz'] ?? '20').toString();
        _precioPaletaCtrl.text = (datos['precio_alquiler_paleta'] ?? '0')
            .toString();
      } else {
        _precioBaseCtrl.text = "4000";
        _precioLuzCtrl.text = "1500";
        _horaLuzCtrl.text = "20";
        _precioPaletaCtrl.text = "800";
      }

      // 2. Cargar Listado de Canchas Fisicas
      final docCanchas = await _firestore
          .collection('configuracion_paddle')
          .doc('canchas')
          .get();
      if (docCanchas.exists && docCanchas.data()?['lista'] != null) {
        setState(() {
          _canchasExistentes = List<String>.from(docCanchas.data()!['lista']);
        });
      } else {
        setState(() {
          _canchasExistentes = [
            "Cancha 1 Cristal",
            "Cancha 2 Cristal",
            "Cancha 3 Muro",
          ];
        });
      }
    } catch (e) {
      _mostrarSnack('❌ Error al recuperar configuraciones: $e', Colors.red);
    } finally {
      setState(() => _cargandoDatos = false);
    }
  }

  /// Guarda de forma síncrona tarifas y el listado de canchas para la grilla
  Future<void> _guardarTodo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    try {
      // Guardar tarifas y reglas nocturnas
      await _firestore
          .collection('configuraciones_paddle')
          .doc('ajustes_globales')
          .set({
            'precio_base_cancha':
                double.tryParse(_precioBaseCtrl.text.trim()) ?? 0.0,
            'precio_adicional_luz':
                double.tryParse(_precioLuzCtrl.text.trim()) ?? 0.0,
            'hora_inicio_luz': int.tryParse(_horaLuzCtrl.text.trim()) ?? 20,
            'precio_alquiler_paleta':
                double.tryParse(_precioPaletaCtrl.text.trim()) ?? 0.0,
            'ultimaModificacion': DateTime.now(),
          }, SetOptions(merge: true));

      // Guardar el ABM estructural de canchas
      await _firestore.collection('configuracion_paddle').doc('canchas').set({
        'lista': _canchasExistentes,
      });

      _mostrarSnack(
        '✅ Configuración y ABM de canchas actualizados en el servidor.',
        Colors.green,
      );
    } catch (e) {
      _mostrarSnack('❌ Error al escribir cambios: $e', Colors.red);
    } finally {
      setState(() => _guardando = false);
    }
  }

  void _agregarCanchaALista() {
    final nombre = _nuevaCanchaCtrl.text.trim();
    if (nombre.isEmpty) return;
    if (_canchasExistentes.contains(nombre)) {
      _mostrarSnack(
        '⚠️ Esa cancha ya se encuentra dada de alta.',
        Colors.orange,
      );
      return;
    }
    setState(() {
      _canchasExistentes.add(nombre);
      _nuevaCanchaCtrl.clear();
    });
  }

  void _removerCanchaDeLista(String nombre) {
    setState(() {
      _canchasExistentes.remove(nombre);
    });
  }

  void _mostrarSnack(String msg, Color c) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoDatos) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.indigo)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(40.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Administración Comercial: Paddle',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Text(
                'Centralizá las tarifas por bloque, horarios de reflectores y control de canchas activas.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // BLOQUE Izquierdo: Tarifas e Iluminación
                  Expanded(
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
                            'Matriz de Precios y Horarios',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _precioBaseCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Precio Base del Turno (Cancha)',
                              border: OutlineInputBorder(),
                              prefixText: '\$ ',
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Campo requerido'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _horaLuzCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Inicio de Luz (24hs)',
                                    border: OutlineInputBorder(),
                                    suffixText: ' hs',
                                  ),
                                  validator: (v) {
                                    final h = int.tryParse(v ?? '');
                                    if (h == null || h < 0 || h > 23) {
                                      return 'Inválido (0-23)';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _precioLuzCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Plus Adicional Luz',
                                    border: OutlineInputBorder(),
                                    prefixText: '\$ ',
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Campo requerido'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _precioPaletaCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Precio Alquiler de Paleta',
                              border: OutlineInputBorder(),
                              prefixText: '\$ ',
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Campo requerido'
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),

                  // BLOQUE Derecho: El ABM de Canchas Físicas Recuperado
                  Expanded(
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
                            'ABM de Canchas del Complejo',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Agregá o eliminá las canchas que aparecerán operativas en la grilla diaria.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 24),

                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _nuevaCanchaCtrl,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Nombre de la Cancha (ej: Cancha 4 Cristal)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(60, 54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: _agregarCanchaALista,
                                child: const Icon(Icons.add),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Canchas en Funcionamiento:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),

                          if (_canchasExistentes.isEmpty)
                            const Text(
                              'No hay canchas dadas de alta en el complejo.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _canchasExistentes.map((cancha) {
                                return Chip(
                                  label: Text(
                                    cancha,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  deleteIcon: const Icon(
                                    Icons.cancel,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onDeleted: () =>
                                      _removerCanchaDeLista(cancha),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Botón único de Guardado Centralizado
              SizedBox(
                height: 52,
                width: 400,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _guardando ? null : _guardarTodo,
                  icon: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text(
                    'Guardar Configuración Comercial y Canchas',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
