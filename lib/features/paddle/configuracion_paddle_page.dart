import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cancha_padel_model.dart';
import 'cancha_padel_repository.dart';
import 'paddle_ids.dart';

const List<String> _tiposSuperficie = ['Cristal', 'Muro', 'Panorámica'];

/// Fila editable del ABM de canchas. No usa TextEditingController (serían
/// decenas por fila dinámica a crear/destruir) — cada TextFormField usa
/// `initialValue` + `onChanged` para mutar esta fila directamente.
class _FilaCanchaPadel {
  String idOriginal; // '' si todavía no se guardó nunca.
  String nombre;
  String tipoSuperficie;
  bool activa;
  bool permiteTurnosFijos;
  String precioSocioTxt;
  String precioExternoTxt;
  String precioLuzTxt;
  String horaLuzTxt;
  int ordenVisualizacion;

  _FilaCanchaPadel({
    required this.idOriginal,
    required this.nombre,
    required this.tipoSuperficie,
    required this.activa,
    required this.permiteTurnosFijos,
    required this.precioSocioTxt,
    required this.precioExternoTxt,
    required this.precioLuzTxt,
    required this.horaLuzTxt,
    required this.ordenVisualizacion,
  });

  factory _FilaCanchaPadel.desdeModelo(CanchaPadelModel c) {
    return _FilaCanchaPadel(
      idOriginal: c.id,
      nombre: c.nombre,
      tipoSuperficie: c.tipoSuperficie,
      activa: c.activa,
      permiteTurnosFijos: c.permiteTurnosFijos,
      precioSocioTxt: c.precioBaseHoraSocio?.toStringAsFixed(0) ?? '',
      precioExternoTxt: c.precioBaseHoraExterno?.toStringAsFixed(0) ?? '',
      precioLuzTxt: c.precioAdicionalLuz?.toStringAsFixed(0) ?? '',
      horaLuzTxt: c.horaInicioLuz?.toString() ?? '',
      ordenVisualizacion: c.ordenVisualizacion,
    );
  }

  factory _FilaCanchaPadel.nueva(int orden) {
    return _FilaCanchaPadel(
      idOriginal: '',
      nombre: '',
      tipoSuperficie: 'Cristal',
      activa: true,
      permiteTurnosFijos: true,
      precioSocioTxt: '',
      precioExternoTxt: '',
      precioLuzTxt: '',
      horaLuzTxt: '',
      ordenVisualizacion: orden,
    );
  }

  CanchaPadelModel aModelo() {
    return CanchaPadelModel(
      id: canchaSinEspacios(nombre),
      nombre: nombre,
      tipoSuperficie: tipoSuperficie,
      activa: activa,
      permiteTurnosFijos: permiteTurnosFijos,
      precioBaseHoraSocio: double.tryParse(precioSocioTxt.trim()),
      precioBaseHoraExterno: double.tryParse(precioExternoTxt.trim()),
      precioAdicionalLuz: double.tryParse(precioLuzTxt.trim()),
      horaInicioLuz: int.tryParse(horaLuzTxt.trim()),
      ordenVisualizacion: ordenVisualizacion,
    );
  }
}

class ConfiguracionPaddlePage extends StatefulWidget {
  const ConfiguracionPaddlePage({super.key});

  @override
  State<ConfiguracionPaddlePage> createState() =>
      _ConfiguracionPaddlePageState();
}

class _ConfiguracionPaddlePageState extends State<ConfiguracionPaddlePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  // Ajustes globales (fallback para cualquier cancha sin override propio).
  final _precioBaseSocioCtrl = TextEditingController();
  final _precioBaseExternoCtrl = TextEditingController();
  final _precioLuzCtrl = TextEditingController();
  final _horaLuzCtrl = TextEditingController();
  final _horaAperturaCtrl = TextEditingController();
  final _horaCierreCtrl = TextEditingController();

  bool _cargandoDatos = true;
  bool _guardando = false;
  bool _migrando = false;
  List<_FilaCanchaPadel> _filas = [];

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _precioBaseSocioCtrl.dispose();
    _precioBaseExternoCtrl.dispose();
    _precioLuzCtrl.dispose();
    _horaLuzCtrl.dispose();
    _horaAperturaCtrl.dispose();
    _horaCierreCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargandoDatos = true);
    try {
      final docAjustes = await _firestore
          .collection('configuraciones_paddle')
          .doc('ajustes_globales')
          .get();
      final datos = docAjustes.data() ?? {};
      _precioBaseSocioCtrl.text = (datos['precio_base_cancha'] ?? 4500)
          .toString();
      _precioBaseExternoCtrl.text = (datos['precio_base_externo'] ?? 6000)
          .toString();
      _precioLuzCtrl.text = (datos['precio_adicional_luz'] ?? 1500)
          .toString();
      _horaLuzCtrl.text = (datos['hora_inicio_luz'] ?? 20).toString();
      _horaAperturaCtrl.text = (datos['hora_apertura'] ?? 8).toString();
      _horaCierreCtrl.text = (datos['hora_cierre'] ?? 23).toString();

      final canchas = await obtenerCanchasPadel(_firestore);
      _filas = canchas.map(_FilaCanchaPadel.desdeModelo).toList();
    } catch (e) {
      _mostrarSnack('❌ Error al recuperar configuraciones: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargandoDatos = false);
    }
  }

  Future<void> _guardarTodo() async {
    if (!_formKey.currentState!.validate()) return;
    for (final fila in _filas) {
      if (fila.nombre.trim().isEmpty) {
        _mostrarSnack(
          '⚠️ Hay una cancha sin nombre — completalo o eliminala.',
          Colors.orange,
        );
        return;
      }
    }

    setState(() => _guardando = true);
    try {
      await _firestore
          .collection('configuraciones_paddle')
          .doc('ajustes_globales')
          .set({
            'precio_base_cancha':
                double.tryParse(_precioBaseSocioCtrl.text.trim()) ?? 0.0,
            'precio_base_externo':
                double.tryParse(_precioBaseExternoCtrl.text.trim()) ?? 0.0,
            'precio_adicional_luz':
                double.tryParse(_precioLuzCtrl.text.trim()) ?? 0.0,
            'hora_inicio_luz': int.tryParse(_horaLuzCtrl.text.trim()) ?? 20,
            'hora_apertura': int.tryParse(_horaAperturaCtrl.text.trim()) ?? 8,
            'hora_cierre': int.tryParse(_horaCierreCtrl.text.trim()) ?? 23,
            'ultimaModificacion': DateTime.now(),
          }, SetOptions(merge: true));

      for (final fila in _filas) {
        final nuevoId = canchaSinEspacios(fila.nombre);
        if (fila.idOriginal.isNotEmpty && fila.idOriginal != nuevoId) {
          await eliminarCanchaPadel(_firestore, fila.idOriginal);
        }
        await guardarCanchaPadel(_firestore, fila.aModelo());
        fila.idOriginal = nuevoId;
      }

      _mostrarSnack('✅ Configuración de pádel actualizada.', Colors.green);
    } catch (e) {
      _mostrarSnack('❌ Error al guardar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _migrarCanchasLegacy() async {
    setState(() => _migrando = true);
    try {
      final migradas = await migrarCanchasLegacyACanchasPadel(_firestore);
      final canchas = await obtenerCanchasPadel(_firestore);
      setState(() => _filas = canchas.map(_FilaCanchaPadel.desdeModelo).toList());
      _mostrarSnack(
        migradas > 0
            ? '✅ Se migraron $migradas cancha/s desde la configuración anterior.'
            : 'No había canchas nuevas para migrar (ya estaban todas acá, o no hay ninguna configurada todavía).',
        Colors.green,
      );
    } catch (e) {
      _mostrarSnack('❌ Error al migrar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _migrando = false);
    }
  }

  void _agregarCancha() {
    setState(() {
      _filas.add(_FilaCanchaPadel.nueva(_filas.length));
    });
  }

  Future<void> _eliminarCancha(_FilaCanchaPadel fila) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar cancha?'),
        content: Text(
          'Se va a eliminar "${fila.nombre}" de la configuración. Esto no '
          'borra las reservas ya hechas en esa cancha.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    if (fila.idOriginal.isNotEmpty) {
      await eliminarCanchaPadel(_firestore, fila.idOriginal);
    }
    setState(() => _filas.remove(fila));
  }

  void _mostrarSnack(String msg, Color c) {
    if (!mounted) return;
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
                'Administración Comercial: Pádel',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Text(
                'Precios de referencia del complejo y precio/horario propios '
                'por cancha (si una cancha no tiene su propio valor cargado, '
                'usa el de referencia).',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // BLOQUE Izquierdo: Ajustes globales de referencia.
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
                            'Precios y Horarios de Referencia',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _precioBaseSocioCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Precio base (Socio)',
                                    border: OutlineInputBorder(),
                                    prefixText: '\$ ',
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Campo requerido'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _precioBaseExternoCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Precio base (Externo)',
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
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _horaAperturaCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Hora de apertura',
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
                                  controller: _horaCierreCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Hora de cierre',
                                    border: OutlineInputBorder(),
                                    suffixText: ' hs',
                                  ),
                                  validator: (v) {
                                    final h = int.tryParse(v ?? '');
                                    if (h == null || h < 1 || h > 24) {
                                      return 'Inválido (1-24)';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'El precio de alquiler de paletas/pelotas ahora se '
                            'carga como producto de Pro-Shop en Inventario '
                            '(tipo "Pro-Shop"), con stock real.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),

                  // BLOQUE Derecho: ABM de canchas (canchas_padel).
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Canchas del Complejo',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_filas.isEmpty)
                                TextButton.icon(
                                  onPressed: _migrando
                                      ? null
                                      : _migrarCanchasLegacy,
                                  icon: _migrando
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.sync, size: 18),
                                  label: const Text(
                                    'Migrar canchas antiguas',
                                  ),
                                ),
                            ],
                          ),
                          const Text(
                            'Dejá el precio/horario de una cancha en blanco '
                            'para que use el valor de referencia de la '
                            'izquierda.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          if (_filas.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No hay canchas cargadas todavía. Usá '
                                '"Migrar canchas antiguas" si ya tenías '
                                'canchas configuradas, o agregá una nueva '
                                'abajo.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else
                            ..._filas.map(_buildFilaCancha),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _agregarCancha,
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar cancha'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

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

  Widget _buildFilaCancha(_FilaCanchaPadel fila) {
    return Container(
      key: ValueKey(fila.idOriginal.isNotEmpty ? fila.idOriginal : fila),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: fila.nombre,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => fila.nombre = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: fila.tipoSuperficie,
                  decoration: const InputDecoration(
                    labelText: 'Superficie',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _tiposSuperficie
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => fila.tipoSuperficie = v ?? 'Cristal'),
                ),
              ),
              IconButton(
                tooltip: 'Eliminar cancha',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _eliminarCancha(fila),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: fila.precioSocioTxt,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio socio (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  onChanged: (v) => fila.precioSocioTxt = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: fila.precioExternoTxt,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio externo (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  onChanged: (v) => fila.precioExternoTxt = v,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: fila.horaLuzTxt,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Inicio de luz (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                    suffixText: ' hs',
                  ),
                  onChanged: (v) => fila.horaLuzTxt = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: fila.precioLuzTxt,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Plus luz (opcional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  onChanged: (v) => fila.precioLuzTxt = v,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activa', style: TextStyle(fontSize: 13)),
                  value: fila.activa,
                  onChanged: (v) => setState(() => fila.activa = v),
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Admite turnos fijos',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: fila.permiteTurnosFijos,
                  onChanged: (v) => setState(() => fila.permiteTurnosFijos = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
