import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'padel_score_engine.dart';
import 'setup_partido_dialog.dart';

const _kFondoOscuro = Color(0xFF0F172A);
const _kPrimary = Color(0xFF0A3B43);

/// Mando auxiliar: controlador pensado para celular o tablet de cancha,
/// pensado para cargar puntos rápido mientras se mira el partido en vivo.
/// Escucha el mismo documento que `MarcadorTvPage` y aplica la lógica de
/// `PadelScoreEngine` sobre el estado recibido por Firestore.
class MarcadorMandoAuxiliarPage extends StatefulWidget {
  final String canchaNombre;

  const MarcadorMandoAuxiliarPage({super.key, required this.canchaNombre});

  @override
  State<MarcadorMandoAuxiliarPage> createState() =>
      _MarcadorMandoAuxiliarPageState();
}

class _MarcadorMandoAuxiliarPageState
    extends State<MarcadorMandoAuxiliarPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final String _idCancha;
  bool _enviando = false;

  // 🎙️ CARGA DE PUNTOS POR VOZ
  //
  // Vocabulario reconocido (sin importar mayúsculas/acentos):
  //   "punto uno" / "pareja uno" / "equipo a"  -> + Punto Pareja 1
  //   "punto dos" / "pareja dos" / "equipo b"  -> + Punto Pareja 2
  //   "deshacer" / "anular"                    -> Deshacer último punto
  //   "saque"                                  -> Cambiar Saque
  //
  // Es sólo un atajo: los botones manuales de abajo siguen siempre activos
  // como contingencia (club de alquiler, sin cancha con bocha de público
  // ni ruido ambiente relevante, pero el micrófono puede fallar igual).
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInicializado = false;
  bool _vozActiva = false;
  bool _microfonoEscuchando = false;
  String? _localeVozEspanol;
  Map<String, dynamic>? _ultimoEstado;
  String? _ultimoComandoEscuchado;
  Timer? _timerLimpiezaFeedback;

  static final RegExp _comandoDeshacer = RegExp(r'\b(deshacer|anular)\b');
  static final RegExp _comandoSaque = RegExp(r'\bsaque\b');
  static final RegExp _comandoPuntoA = RegExp(
    r'\b(punto\s*uno|pareja\s*uno|equipo\s*a|punto\s*a)\b',
  );
  static final RegExp _comandoPuntoB = RegExp(
    r'\b(punto\s*dos|pareja\s*dos|equipo\s*b|punto\s*b)\b',
  );

  @override
  void initState() {
    super.initState();
    _idCancha = PadelScoreEngine.idDocumentoDesdeCancha(widget.canchaNombre);
  }

  @override
  void dispose() {
    _timerLimpiezaFeedback?.cancel();
    if (_speechInicializado) _speech.stop();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _firestore.collection('partidos_marcador').doc(_idCancha);

  Future<void> _alternarVoz() async {
    if (_vozActiva) {
      setState(() => _vozActiva = false);
      await _speech.stop();
      return;
    }

    if (!_speechInicializado) {
      final disponible = await _speech.initialize(
        onStatus: _onEstadoVoz,
        onError: _onErrorVoz,
      );
      _speechInicializado = disponible;
      if (!disponible) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'El reconocimiento de voz no está disponible en este '
                'dispositivo. Usá los botones manuales.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final locales = await _speech.locales();
      final espanol = locales.where(
        (l) => l.localeId.toLowerCase().startsWith('es'),
      );
      _localeVozEspanol =
          espanol.isNotEmpty ? espanol.first.localeId : null;
    }

    setState(() => _vozActiva = true);
    _escucharCiclo();
  }

  void _escucharCiclo() {
    if (!_vozActiva || !mounted) return;
    _speech.listen(
      onResult: _onResultadoVoz,
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: false,
        cancelOnError: false,
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
        localeId: _localeVozEspanol,
      ),
    );
  }

  void _onEstadoVoz(String status) {
    if (!mounted) return;
    setState(() => _microfonoEscuchando = status == 'listening');
    if ((status == 'done' || status == 'notListening') && _vozActiva) {
      // 🔁 Relanza un nuevo ciclo corto de escucha: así queda "siempre
      // escuchando" sin pisar los topes de duración que impone el SO.
      Future.delayed(const Duration(milliseconds: 400), _escucharCiclo);
    }
  }

  void _onErrorVoz(dynamic error) {
    // Errores transitorios (silencio, "no match", etc.): el callback de
    // estado ya se encarga de relanzar el próximo ciclo de escucha.
  }

  void _onResultadoVoz(SpeechRecognitionResult resultado) {
    if (!resultado.finalResult) return;
    _procesarComandoDeVoz(resultado.recognizedWords);
  }

  String _normalizarTexto(String texto) {
    const conAcentos = 'áéíóúÁÉÍÓÚñÑ';
    const sinAcentos = 'aeiouAEIOUnN';
    String normalizado = texto;
    for (int i = 0; i < conAcentos.length; i++) {
      normalizado = normalizado.replaceAll(conAcentos[i], sinAcentos[i]);
    }
    return normalizado.toLowerCase().trim();
  }

  void _procesarComandoDeVoz(String textoReconocido) {
    final estado = _ultimoEstado;
    if (estado == null || _enviando) return;
    final texto = _normalizarTexto(textoReconocido);
    if (texto.isEmpty) return;

    if (_comandoDeshacer.hasMatch(texto)) {
      final historial = estado['historial'] as List<dynamic>? ?? [];
      if (historial.isEmpty) return;
      _marcarComandoReconocido('Deshacer');
      _aplicar(PadelScoreEngine.deshacerPunto, estado);
      return;
    }

    if (estado['partidoFinalizado'] == true) return;

    if (_comandoSaque.hasMatch(texto)) {
      _marcarComandoReconocido('Cambiar Saque');
      _aplicar(PadelScoreEngine.alternarSaque, estado);
      return;
    }
    if (_comandoPuntoA.hasMatch(texto)) {
      _marcarComandoReconocido('+ Punto Pareja 1');
      _aplicar((e) => PadelScoreEngine.sumarPunto(e, 'A'), estado);
      return;
    }
    if (_comandoPuntoB.hasMatch(texto)) {
      _marcarComandoReconocido('+ Punto Pareja 2');
      _aplicar((e) => PadelScoreEngine.sumarPunto(e, 'B'), estado);
      return;
    }
  }

  void _marcarComandoReconocido(String etiqueta) {
    if (!mounted) return;
    _timerLimpiezaFeedback?.cancel();
    setState(() => _ultimoComandoEscuchado = etiqueta);
    _timerLimpiezaFeedback = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _ultimoComandoEscuchado = null);
    });
  }

  Future<void> _aplicar(
    Map<String, dynamic> Function(Map<String, dynamic>) transformacion,
    Map<String, dynamic> estadoActual,
  ) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      final nuevoEstado = transformacion(estadoActual);
      await _docRef.set(nuevoEstado);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar el marcador: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirConfiguracion() async {
    final iniciado = await showDialog<bool>(
      context: context,
      builder: (_) => SetupPartidoDialog(canchaNombre: widget.canchaNombre),
    );
    if (iniciado == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Partido iniciado. Ya se puede cargar puntos.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _confirmarYReconfigurar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Configurar un nuevo partido?'),
        content: const Text(
          'Esto reemplaza el marcador actual de esta cancha por uno nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sí, reconfigurar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmar == true) _abrirConfiguracion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kFondoOscuro,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: Text('Mando · ${widget.canchaNombre}'),
        actions: [
          IconButton(
            tooltip: _vozActiva
                ? 'Apagar Carga de Puntos por Voz'
                : 'Activar Carga de Puntos por Voz',
            icon: Icon(
              _vozActiva
                  ? (_microfonoEscuchando ? Icons.mic : Icons.mic_none)
                  : Icons.mic_off,
              color: _vozActiva ? Colors.redAccent : Colors.white,
            ),
            onPressed: _alternarVoz,
          ),
          IconButton(
            tooltip: 'Configurar Nuevo Partido',
            icon: const Icon(Icons.settings),
            onPressed: _confirmarYReconfigurar,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _docRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final data = snapshot.data?.data();
          final bool activo = data != null && data['activo'] == true;
          _ultimoEstado = activo ? data : null;

          if (!activo) {
            return _buildSinPartido();
          }

          return _buildControlador(data);
        },
      ),
    );
  }

  Widget _buildSinPartido() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sports_tennis,
              size: 64,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            const Text(
              'No hay un partido en curso en esta cancha.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              onPressed: _abrirConfiguracion,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Configurar Partido'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlador(Map<String, dynamic> estado) {
    final equipoA = Map<String, dynamic>.from(estado['equipoA'] ?? {});
    final equipoB = Map<String, dynamic>.from(estado['equipoB'] ?? {});
    final String modoJuego = estado['modoJuego']?.toString() ??
        PadelScoreEngine.modoPuntoDeOro;
    final bool enTiebreak = estado['enTiebreak'] == true;
    final bool finalizado = estado['partidoFinalizado'] == true;
    final String saque = estado['saque']?.toString() ?? 'A';

    final String puntosLabelA = enTiebreak
        ? '${(estado['puntosTiebreakA'] as num?)?.toInt() ?? 0}'
        : PadelScoreEngine.etiquetaPunto(
            puntos: (estado['puntosA'] as num?)?.toInt() ?? 0,
            puntosRival: (estado['puntosB'] as num?)?.toInt() ?? 0,
            modoJuego: modoJuego,
          );
    final String puntosLabelB = enTiebreak
        ? '${(estado['puntosTiebreakB'] as num?)?.toInt() ?? 0}'
        : PadelScoreEngine.etiquetaPunto(
            puntos: (estado['puntosB'] as num?)?.toInt() ?? 0,
            puntosRival: (estado['puntosA'] as num?)?.toInt() ?? 0,
            modoJuego: modoJuego,
          );

    final historial = estado['historial'] as List<dynamic>? ?? [];
    final bool hayHistorial = historial.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (finalizado)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green),
                ),
                child: Text(
                  '🏆 Partido finalizado · Ganó Equipo ${estado['ganadorPartido'] ?? '-'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (_vozActiva) _buildBannerVoz(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _buildPanelEquipo(
                      nombre: equipoA['nombre']?.toString() ?? 'Pareja A',
                      puntos: puntosLabelA,
                      games: (estado['gamesA'] as num?)?.toInt() ?? 0,
                      sets: (estado['setsGanadosA'] as num?)?.toInt() ?? 0,
                      sirviendo: saque == 'A',
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPanelEquipo(
                      nombre: equipoB['nombre']?.toString() ?? 'Pareja B',
                      puntos: puntosLabelB,
                      games: (estado['gamesB'] as num?)?.toInt() ?? 0,
                      sets: (estado['setsGanadosB'] as num?)?.toInt() ?? 0,
                      sirviendo: saque == 'B',
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: finalizado || _enviando
                        ? null
                        : () => _aplicar(
                              (e) => PadelScoreEngine.sumarPunto(e, 'A'),
                              estado,
                            ),
                    child: const Text(
                      '+ PUNTO PAREJA 1',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: finalizado || _enviando
                        ? null
                        : () => _aplicar(
                              (e) => PadelScoreEngine.sumarPunto(e, 'B'),
                              estado,
                            ),
                    child: const Text(
                      '+ PUNTO PAREJA 2',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: !hayHistorial || _enviando
                        ? null
                        : () => _aplicar(
                              PadelScoreEngine.deshacerPunto,
                              estado,
                            ),
                    icon: const Icon(Icons.undo),
                    label: const Text('Deshacer'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: finalizado || _enviando
                        ? null
                        : () => _aplicar(
                              PadelScoreEngine.alternarSaque,
                              estado,
                            ),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Cambiar Saque'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerVoz() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _microfonoEscuchando ? Icons.mic : Icons.mic_none,
            color: _microfonoEscuchando ? Colors.redAccent : Colors.white38,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _ultimoComandoEscuchado != null
                  ? '🎙️ Comando reconocido: $_ultimoComandoEscuchado'
                  : 'Escuchando… decí "punto uno", "punto dos", "deshacer" o "saque"',
              style: TextStyle(
                color: _ultimoComandoEscuchado != null
                    ? Colors.greenAccent
                    : Colors.white54,
                fontSize: 12,
                fontWeight: _ultimoComandoEscuchado != null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelEquipo({
    required String nombre,
    required String puntos,
    required int games,
    required int sets,
    required bool sirviendo,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: sirviendo ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (sirviendo) ...[
                const Icon(
                  Icons.sports_tennis,
                  color: Colors.amber,
                  size: 16,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  nombre,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            puntos,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 44,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Games: $games   ·   Sets: $sets',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
