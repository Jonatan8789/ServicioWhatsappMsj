import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'padel_score_engine.dart';

const _kFondoOscuro = Color(0xFF0F172A);
const _kPrimary = Color(0xFF0A3B43);

/// Pantalla de TV / proyector de cancha: marcador de alto contraste pensado
/// para leerse a distancia. Se queda escuchando en vivo el documento de
/// `partidos_marcador/{idCancha}` y cae a un screensaver del club cuando no
/// hay ningún partido activo.
class MarcadorTvPage extends StatelessWidget {
  final String canchaNombre;

  const MarcadorTvPage({super.key, required this.canchaNombre});

  @override
  Widget build(BuildContext context) {
    final idCancha = PadelScoreEngine.idDocumentoDesdeCancha(canchaNombre);
    final docRef = FirebaseFirestore.instance
        .collection('partidos_marcador')
        .doc(idCancha);

    return Scaffold(
      backgroundColor: _kFondoOscuro,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final bool activo = data != null && data['activo'] == true;

          if (!activo) {
            return _Screensaver(canchaNombre: canchaNombre);
          }

          return _MarcadorEnVivo(canchaNombre: canchaNombre, estado: data);
        },
      ),
    );
  }
}

class _Screensaver extends StatelessWidget {
  final String canchaNombre;

  const _Screensaver({required this.canchaNombre});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: const Icon(
              Icons.sports_tennis,
              size: 72,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'OQUA CLUB',
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            canchaNombre.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 20,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.greenAccent),
            ),
            child: const Text(
              'CANCHA DISPONIBLE',
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarcadorEnVivo extends StatelessWidget {
  final String canchaNombre;
  final Map<String, dynamic> estado;

  const _MarcadorEnVivo({required this.canchaNombre, required this.estado});

  @override
  Widget build(BuildContext context) {
    final equipoA = Map<String, dynamic>.from(estado['equipoA'] ?? {});
    final equipoB = Map<String, dynamic>.from(estado['equipoB'] ?? {});
    final String modoJuego =
        estado['modoJuego']?.toString() ?? PadelScoreEngine.modoPuntoDeOro;
    final bool enTiebreak = estado['enTiebreak'] == true;
    final bool finalizado = estado['partidoFinalizado'] == true;
    final String saque = estado['saque']?.toString() ?? 'A';

    final String puntosA = enTiebreak
        ? '${(estado['puntosTiebreakA'] as num?)?.toInt() ?? 0}'
        : PadelScoreEngine.etiquetaPunto(
            puntos: (estado['puntosA'] as num?)?.toInt() ?? 0,
            puntosRival: (estado['puntosB'] as num?)?.toInt() ?? 0,
            modoJuego: modoJuego,
          );
    final String puntosB = enTiebreak
        ? '${(estado['puntosTiebreakB'] as num?)?.toInt() ?? 0}'
        : PadelScoreEngine.etiquetaPunto(
            puntos: (estado['puntosB'] as num?)?.toInt() ?? 0,
            puntosRival: (estado['puntosA'] as num?)?.toInt() ?? 0,
            modoJuego: modoJuego,
          );

    final setsCompletados = (estado['setsCompletados'] as List<dynamic>? ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          children: [
            _buildEncabezado(setsCompletados, finalizado),
            const SizedBox(height: 28),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildColumnaEquipo(
                      equipo: equipoA,
                      puntos: puntosA,
                      games: (estado['gamesA'] as num?)?.toInt() ?? 0,
                      sirviendo: saque == 'A',
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    color: Colors.white12,
                  ),
                  Expanded(
                    child: _buildColumnaEquipo(
                      equipo: equipoB,
                      puntos: puntosB,
                      games: (estado['gamesB'] as num?)?.toInt() ?? 0,
                      sirviendo: saque == 'B',
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
            if (enTiebreak && !finalizado) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Text(
                  'TIE-BREAK',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEncabezado(
    List<Map<String, dynamic>> setsCompletados,
    bool finalizado,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: _kPrimary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            canchaNombre.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),
          if (finalizado)
            const Text(
              '🏆 PARTIDO FINALIZADO',
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            )
          else if (setsCompletados.isNotEmpty)
            Wrap(
              spacing: 16,
              children: [
                for (int i = 0; i < setsCompletados.length; i++)
                  Text(
                    'Set ${i + 1}: ${setsCompletados[i]['a']}-${setsCompletados[i]['b']}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildColumnaEquipo({
    required Map<String, dynamic> equipo,
    required String puntos,
    required int games,
    required bool sirviendo,
    required Color color,
  }) {
    final jugadores = (equipo['jugadores'] as List<dynamic>? ?? [])
        .map((j) => Map<String, dynamic>.from(j as Map))
        .toList();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (sirviendo) ...[
              const Icon(
                Icons.sports_tennis,
                color: Colors.amber,
                size: 28,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                (equipo['nombre'] ?? '').toString(),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: jugadores
              .map((j) => _buildFotoJugador(j, color))
              .expand((w) => [w, const SizedBox(width: 16)])
              .toList()
            ..removeLast(),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: FittedBox(
            fit: BoxFit.contain,
            child: Text(
              puntos,
              style: TextStyle(
                color: color,
                fontSize: 180,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'GAMES: $games',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFotoJugador(Map<String, dynamic> jugador, Color color) {
    final String fotoUrl = (jugador['fotoUrl'] ?? '').toString();
    final String nombre = (jugador['nombre'] ?? '').toString();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: color.withValues(alpha: 0.2),
          backgroundImage:
              fotoUrl.isNotEmpty ? CachedNetworkImageProvider(fotoUrl) : null,
          child: fotoUrl.isEmpty
              ? Text(
                  nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 90,
          child: Text(
            nombre,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
