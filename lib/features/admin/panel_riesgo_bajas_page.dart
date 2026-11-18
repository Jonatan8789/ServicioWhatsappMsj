import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';

/// Detecta socios en riesgo de baja combinando dos señales: hace cuánto que
/// no vienen y si tienen cuota pendiente — para que el club pueda actuar
/// ANTES de perderlos, en vez de enterarse cuando ya dejaron de pagar del
/// todo. Ambas lecturas son puntuales (no en vivo) y acotadas: no escanea
/// toda la colección de asistencias, sólo la ventana de días elegida.
class _SocioEnRiesgo {
  final String id;
  final String nombre;
  final String telefono;
  final bool sinAsistenciaReciente;
  final double deuda;
  final List<String> periodosPendientes;

  _SocioEnRiesgo({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.sinAsistenciaReciente,
    required this.deuda,
    required this.periodosPendientes,
  });

  int get puntajeRiesgo =>
      (sinAsistenciaReciente ? 1 : 0) + (deuda > 0 ? 1 : 0);
}

class PanelRiesgoBajasPage extends StatefulWidget {
  const PanelRiesgoBajasPage({super.key});

  @override
  State<PanelRiesgoBajasPage> createState() => _PanelRiesgoBajasPageState();
}

class _PanelRiesgoBajasPageState extends State<PanelRiesgoBajasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _diasInactividad = 30;
  bool _cargando = true;
  String? _error;
  List<_SocioEnRiesgo> _enRiesgo = [];
  String _filtro = 'Todos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, String>> _headersWhatsapp() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // 1) Socios activos — una sola lectura, no en vivo (mismo patrón ya
      // usado en socios_page.dart / reportes_bi_page.dart).
      final sociosSnap = await _firestore
          .collection('socios')
          .where('activo', isEqualTo: true)
          .get();

      // 2) Quiénes vinieron dentro de la ventana elegida — acotado por
      // fecha, no escanea el historial completo de asistencias.
      final DateTime corte = DateTime.now().subtract(Duration(days: _diasInactividad));
      final asistSnap = await _firestore
          .collection('asistencias_accesos')
          .where('fechaHora', isGreaterThanOrEqualTo: Timestamp.fromDate(corte))
          .get();
      final Set<String> visitaronReciente = asistSnap.docs
          .map((d) => (d.data())['socioId']?.toString())
          .whereType<String>()
          .toSet();

      // 3) Cuotas pendientes — mismo patrón (collectionGroup + filtro por
      // tipo/estado + agrupado por socio padre) que ya usa
      // functions/index.js (recordatoriosDiarios), para no duplicar
      // criterios distintos de "qué es una deuda".
      final pendientesSnap = await _firestore
          .collectionGroup('cuenta_corriente')
          .where('estado', isEqualTo: 'Pendiente')
          .get();

      final Map<String, double> deudaPorSocio = {};
      final Map<String, List<String>> periodosPorSocio = {};
      for (final doc in pendientesSnap.docs) {
        final data = doc.data();
        if (data['tipo'] != 'Cuota Mensual') continue;
        final socioRef = doc.reference.parent.parent;
        if (socioRef == null) continue;
        deudaPorSocio[socioRef.id] =
            (deudaPorSocio[socioRef.id] ?? 0) + ((data['monto'] as num?)?.toDouble() ?? 0);
        if (data['periodo'] != null) {
          (periodosPorSocio[socioRef.id] ??= []).add(data['periodo'].toString());
        }
      }

      final List<_SocioEnRiesgo> resultado = [];
      for (final doc in sociosSnap.docs) {
        final data = doc.data();
        final bool sinAsistencia = !visitaronReciente.contains(doc.id);
        final double deuda = deudaPorSocio[doc.id] ?? 0.0;
        if (!sinAsistencia && deuda <= 0) continue; // no está en riesgo
        resultado.add(
          _SocioEnRiesgo(
            id: doc.id,
            nombre: data['nombre']?.toString() ?? 'Socio',
            telefono: data['telefono']?.toString() ?? '',
            sinAsistenciaReciente: sinAsistencia,
            deuda: deuda,
            periodosPendientes: periodosPorSocio[doc.id] ?? [],
          ),
        );
      }
      resultado.sort((a, b) => b.puntajeRiesgo.compareTo(a.puntajeRiesgo));

      if (mounted) {
        setState(() {
          _enRiesgo = resultado;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  Future<void> _avisarPorWhatsapp(_SocioEnRiesgo socio) async {
    if (socio.telefono.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este socio no tiene teléfono registrado.')),
      );
      return;
    }
    String limpio = socio.telefono.replaceAll(RegExp(r'\D'), '');
    if (limpio.startsWith('0')) limpio = limpio.substring(1);
    if (limpio.startsWith('15')) limpio = limpio.substring(2);
    if (!limpio.startsWith('54')) limpio = '549$limpio';

    final buffer = StringBuffer();
    buffer.writeln('¡Hola ${socio.nombre}! 👋 Somos de OQUA Club.');
    if (socio.sinAsistenciaReciente) {
      buffer.writeln('Hace un tiempo que no te vemos por el club — ¡te extrañamos!');
    }
    if (socio.deuda > 0) {
      buffer.writeln(
        'Además, tenés una cuota pendiente de \$${socio.deuda.toStringAsFixed(2)} '
        '(${socio.periodosPendientes.join(', ')}). Cualquier cosa que necesites para regularizarla, contactanos.',
      );
    }
    buffer.writeln('¡Esperamos verte pronto!');

    try {
      final resp = await http.post(
        Uri.parse('https://servicio-whatsapp-oqua.onrender.com/send-whatsapp'),
        headers: await _headersWhatsapp(),
        body: jsonEncode({'phone': limpio, 'message': buffer.toString()}),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              resp.statusCode == 200
                  ? '✅ Mensaje enviado a ${socio.nombre}.'
                  : '⚠️ No se pudo enviar (${resp.statusCode}).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Error al enviar: $e')),
        );
      }
    }
  }

  List<_SocioEnRiesgo> get _filtrados {
    switch (_filtro) {
      case 'Inasistencia':
        return _enRiesgo.where((s) => s.sinAsistenciaReciente).toList();
      case 'Deuda':
        return _enRiesgo.where((s) => s.deuda > 0).toList();
      case 'Ambos':
        return _enRiesgo.where((s) => s.sinAsistenciaReciente && s.deuda > 0).toList();
      default:
        return _enRiesgo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Panel de Riesgo de Bajas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargando ? null : _cargar,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Socios activos que hace tiempo no vienen y/o tienen cuota pendiente — '
              'para contactarlos antes de que se den de baja, no después.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Sin venir hace más de:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<int>(
                    initialValue: _diasInactividad,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: const [15, 30, 45, 60, 90]
                        .map((d) => DropdownMenuItem(value: d, child: Text('$d días')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _diasInactividad = v);
                        _cargar();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: _filtro == 'Todos',
                  onSelected: (_) => setState(() => _filtro = 'Todos'),
                ),
                ChoiceChip(
                  label: const Text('🚶 Sólo inasistencia'),
                  selected: _filtro == 'Inasistencia',
                  onSelected: (_) => setState(() => _filtro = 'Inasistencia'),
                ),
                ChoiceChip(
                  label: const Text('💸 Sólo deuda'),
                  selected: _filtro == 'Deuda',
                  onSelected: (_) => setState(() => _filtro = 'Deuda'),
                ),
                ChoiceChip(
                  label: const Text('⚠️ Ambas señales'),
                  selected: _filtro == 'Ambos',
                  selectedColor: Colors.red.shade100,
                  onSelected: (_) => setState(() => _filtro = 'Ambos'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_cargando && _error == null)
              Text(
                '${lista.length} socio(s) en riesgo de un total de ${_enRiesgo.length} detectados.',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('Error al cargar: $_error'))
                      : lista.isEmpty
                          ? const Center(
                              child: Text(
                                'Ningún socio activo coincide con este filtro — buena señal.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              itemCount: lista.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _buildTarjetaSocio(lista[i]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaSocio(_SocioEnRiesgo socio) {
    final bool riesgoAlto = socio.sinAsistenciaReciente && socio.deuda > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: riesgoAlto ? Colors.red.shade300 : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: riesgoAlto ? Colors.red.shade50 : Colors.orange.shade50,
            child: Icon(
              riesgoAlto ? Icons.priority_high_rounded : Icons.info_outline_rounded,
              color: riesgoAlto ? Colors.red : Colors.orange,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(socio.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (socio.sinAsistenciaReciente)
                      _chipMotivo('Sin venir hace ${_diasInactividad}+ días', Colors.orange),
                    if (socio.deuda > 0)
                      _chipMotivo('Cuota pendiente \$${socio.deuda.toStringAsFixed(0)}', Colors.red),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade700),
            onPressed: () => _avisarPorWhatsapp(socio),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('WhatsApp'),
          ),
        ],
      ),
    );
  }

  Widget _chipMotivo(String texto, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800),
      ),
    );
  }
}
