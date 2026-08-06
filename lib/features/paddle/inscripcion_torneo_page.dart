import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InscripcionTorneoPage extends StatefulWidget {
  final String torneoId;
  final Map<String, dynamic> datosTorneo;

  const InscripcionTorneoPage({
    super.key,
    required this.torneoId,
    required this.datosTorneo,
  });

  @override
  State<InscripcionTorneoPage> createState() => _InscripcionTorneoPageState();
}

class _InscripcionTorneoPageState extends State<InscripcionTorneoPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dniJ1Controller = TextEditingController();
  final TextEditingController _dniJ2Controller = TextEditingController();

  bool _cargando = false;
  String? _errorMensaje;

  // Mapa para orden jerárquico de categorías (1ra es la más alta, Principiantes la más baja)
  final Map<String, int> _jerarquiaCategorias = {
    '1ra': 1,
    '2da': 2,
    '3ra': 3,
    '4ta': 4,
    '5ta': 5,
    '6ta': 6,
    '7ta': 7,
    'Principiantes': 8,
  };

  Future<Map<String, dynamic>?> _obtenerSocioPorDni(String dni) async {
    final String dniLimpio = dni.trim().replaceAll('.', '');
    final int? dniNum = int.tryParse(dniLimpio);

    // Buscar como String
    QuerySnapshot q = await FirebaseFirestore.instance
        .collection('socios')
        .where('dni', isEqualTo: dniLimpio)
        .limit(1)
        .get();

    // Buscar como Int
    if (q.docs.isEmpty && dniNum != null) {
      q = await FirebaseFirestore.instance
          .collection('socios')
          .where('dni', isEqualTo: dniNum)
          .limit(1)
          .get();
    }

    if (q.docs.isNotEmpty) {
      final data = q.docs.first.data() as Map<String, dynamic>;
      data['id'] = q.docs.first.id;
      return data;
    }
    return null;
  }

  Future<void> _procesarInscripcion() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    try {
      final dniJ1 = _dniJ1Controller.text.trim();
      final dniJ2 = _dniJ2Controller.text.trim();

      if (dniJ1 == dniJ2) {
        throw 'Los DNI de ambos jugadores deben ser distintos.';
      }

      // 1. Buscar ambos jugadores en el padrón
      final socio1 = await _obtenerSocioPorDni(dniJ1);
      final socio2 = await _obtenerSocioPorDni(dniJ2);

      if (socio1 == null)
        throw 'No se encontró al Jugador 1 (DNI $dniJ1) en el padrón de socios.';
      if (socio2 == null)
        throw 'No se encontró al Jugador 2 (DNI $dniJ2) en el padrón de socios.';

      // 2. Validar Categorías
      final String catTorneo = widget.datosTorneo['categoria'] ?? '5ta';
      final int nivelTorneo = _jerarquiaCategorias[catTorneo] ?? 5;

      final String catJ1 = socio1['categoriaPaddle'] ?? '5ta';
      final String catJ2 = socio2['categoriaPaddle'] ?? '5ta';

      final int nivelJ1 = _jerarquiaCategorias[catJ1] ?? 5;
      final int nivelJ2 = _jerarquiaCategorias[catJ2] ?? 5;

      // Si el número de jerarquía es MENOR, la categoría es SUPERIOR (Ej: 4ta es nivel 4, superior a 5ta nivel 5)
      if (nivelJ1 < nivelTorneo) {
        throw '${socio1['nombre']} es categoría $catJ1 y no puede anotarse en un torneo de $catTorneo.';
      }
      if (nivelJ2 < nivelTorneo) {
        throw '${socio2['nombre']} es categoría $catJ2 y no puede anotarse en un torneo de $catTorneo.';
      }

      // 3. Registrar Pareja en Firestore
      final Map<String, dynamic> nuevaPareja = {
        'idPareja': 'pareja_${DateTime.now().millisecondsSinceEpoch}',
        'jugador1': {
          'socioId': socio1['id'],
          'nombre': '${socio1['nombre']} ${socio1['apellido'] ?? ''}'.trim(),
          'dni': dniJ1,
          'categoria': catJ1,
        },
        'jugador2': {
          'socioId': socio2['id'],
          'nombre': '${socio2['nombre']} ${socio2['apellido'] ?? ''}'.trim(),
          'dni': dniJ2,
          'categoria': catJ2,
        },
        'pagado': false,
        'fechaInscripcion': DateTime.now().toIso8601String(),
      };

      await FirebaseFirestore.instance
          .collection('torneos')
          .doc(widget.torneoId)
          .update({
            'parejas': FieldValue.arrayUnion([nuevaPareja]),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Pareja inscripta con éxito!'),
            backgroundColor: Color(0xFF0A3B43),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _errorMensaje = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color oquaPrimary = Color(0xFF0A3B43);

    return Scaffold(
      appBar: AppBar(
        title: Text('Inscripción: ${widget.datosTorneo['nombre']}'),
        backgroundColor: oquaPrimary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 550),
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
                  Text(
                    'Categoría Torneo: ${widget.datosTorneo['categoria']} | ${widget.datosTorneo['rama']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: oquaPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_errorMensaje != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMensaje!,
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _dniJ1Controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'DNI Jugador 1',
                      prefixIcon: const Icon(Icons.person, color: oquaPrimary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _dniJ2Controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'DNI Jugador 2',
                      prefixIcon: const Icon(
                        Icons.person_outline,
                        color: oquaPrimary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 24),

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
                          onPressed: _procesarInscripcion,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Validar e Inscribir Pareja'),
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
