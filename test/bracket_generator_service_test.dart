import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/paddle/bracket_generator_service.dart';
import 'package:natatorio_app/features/paddle/partido_torneo_model.dart';

void main() {
  List<ParejaSeed> seeds(int n) =>
      List.generate(n, (i) => ParejaSeed(id: 'p$i', nombre: 'Pareja $i'));

  group('generarEliminacionSimple', () {
    test('N=6: 3 rondas (4+2+1), 2 BYEs en ronda 1, propagados a ronda 2', () {
      final llave = BracketGeneratorService.generarEliminacionSimple(seeds(6));
      final porRonda = <int, List<PartidoTorneo>>{};
      for (final p in llave) {
        porRonda.putIfAbsent(p.ronda, () => []).add(p);
      }

      expect(porRonda[1]!.length, 4);
      expect(porRonda[2]!.length, 2);
      expect(porRonda[3]!.length, 1);

      final byesR1 = porRonda[1]!.where((p) => p.esBye).length;
      expect(byesR1, 2);

      final r1Byes = porRonda[1]!.where((p) => p.esBye);
      for (final p in r1Byes) {
        expect(p.estado, 'Jugado');
        expect(p.ganador, isNotNull);
      }

      final cargadosEnR2 = porRonda[2]!
          .where((p) => p.parejaAId != null || p.parejaBId != null)
          .length;
      expect(cargadosEnR2, 2);
    });

    test('N=5: 3 BYEs repartidos sin chocar entre sí (bracket de 8)', () {
      final llave = BracketGeneratorService.generarEliminacionSimple(seeds(5));
      final r1 = llave.where((p) => p.ronda == 1).toList();
      expect(r1.length, 4);
      expect(r1.where((p) => p.esBye).length, 3);
      // Ningún partido debe tener BYE en ambos lados (dos fantasmas
      // enfrentados no tendría sentido).
      expect(r1.where((p) => p.esByeA && p.esByeB), isEmpty);
    });

    test('N=8 exacto: sin BYEs, 3 rondas hasta la final (4+2+1 partidos)', () {
      final llave = BracketGeneratorService.generarEliminacionSimple(seeds(8));
      final r1 = llave.where((p) => p.ronda == 1).toList();
      expect(r1.every((p) => !p.esBye), isTrue);
      final rondas = llave.map((p) => p.ronda).toSet();
      expect(rondas, {1, 2, 3});
      final final_ = llave.firstWhere((p) => p.ronda == 3);
      expect(final_.siguientePartidoId, isNull);
    });

    test('N<2 no genera nada', () {
      expect(BracketGeneratorService.generarEliminacionSimple(seeds(1)), isEmpty);
      expect(BracketGeneratorService.generarEliminacionSimple([]), isEmpty);
    });

    test('cada partido no-final enlaza a un siguiente válido', () {
      final llave = BracketGeneratorService.generarEliminacionSimple(seeds(16));
      final ids = llave.map((p) => p.id).toSet();
      final maxRonda = llave.map((p) => p.ronda).reduce((a, b) => a > b ? a : b);
      for (final p in llave) {
        if (p.ronda == maxRonda) {
          expect(p.siguientePartidoId, isNull);
        } else {
          expect(p.siguientePartidoId, isNotNull);
          expect(ids.contains(p.siguientePartidoId), isTrue);
        }
      }
    });
  });

  group('distribuirEnGrupos', () {
    test('reparto serpiente: 9 parejas en 3 grupos da 3 cada uno', () {
      final grupos = BracketGeneratorService.distribuirEnGrupos(seeds(9), 3);
      expect(grupos.length, 3);
      for (final lista in grupos.values) {
        expect(lista.length, 3);
      }
      // La mejor semilla (p0) y la segunda mejor (p1) no deben terminar en
      // la misma zona (eso es lo que evita el reparto serpiente).
      final zonaDeP0 = grupos.entries.firstWhere((e) => e.value.any((p) => p.id == 'p0')).key;
      final zonaDeP1 = grupos.entries.firstWhere((e) => e.value.any((p) => p.id == 'p1')).key;
      expect(zonaDeP0 == zonaDeP1, isFalse);
    });
  });

  group('generarRoundRobinZona', () {
    test('3 parejas -> 3 partidos (todos contra todos, una vez cada uno)', () {
      final partidos = BracketGeneratorService.generarRoundRobinZona(
        'ZonaA',
        seeds(3),
      );
      expect(partidos.length, 3);
      final pares = partidos
          .map((p) => ({p.parejaAId, p.parejaBId}))
          .toSet();
      expect(pares.length, 3); // 3 enfrentamientos distintos, sin repetir
    });

    test('4 parejas -> 6 partidos, cada pareja juega exactamente 3', () {
      final partidos = BracketGeneratorService.generarRoundRobinZona(
        'ZonaB',
        seeds(4),
      );
      expect(partidos.length, 6);
      final conteo = <String, int>{};
      for (final p in partidos) {
        conteo[p.parejaAId!] = (conteo[p.parejaAId!] ?? 0) + 1;
        conteo[p.parejaBId!] = (conteo[p.parejaBId!] ?? 0) + 1;
      }
      for (final c in conteo.values) {
        expect(c, 3);
      }
    });
  });

  group('calcularPosiciones', () {
    test('ordena por partidos ganados, luego diferencia de sets/games', () {
      final grupo = seeds(3);
      final partidos = BracketGeneratorService.generarRoundRobinZona(
        'ZonaA',
        grupo,
      );

      final jugados = partidos.map((p) {
        final aEsP0 = p.parejaAId == 'p0';
        final bEsP0 = p.parejaBId == 'p0';
        final aEsP1 = p.parejaAId == 'p1';
        String ganador;
        List<SetJugado> sets;
        if (aEsP0 || bEsP0) {
          ganador = aEsP0 ? 'A' : 'B';
          sets = [
            SetJugado(gamesA: aEsP0 ? 6 : 2, gamesB: aEsP0 ? 2 : 6),
            SetJugado(gamesA: aEsP0 ? 6 : 3, gamesB: aEsP0 ? 3 : 6),
          ];
        } else {
          ganador = aEsP1 ? 'A' : 'B';
          sets = [
            SetJugado(gamesA: aEsP1 ? 6 : 4, gamesB: aEsP1 ? 4 : 6),
            SetJugado(gamesA: aEsP1 ? 6 : 2, gamesB: aEsP1 ? 2 : 6),
          ];
        }
        return p.copyWith(estado: 'Jugado', ganador: ganador, sets: sets);
      }).toList();

      final posiciones = BracketGeneratorService.calcularPosiciones(
        grupo,
        jugados,
      );

      expect(posiciones[0].parejaId, 'p0');
      expect(posiciones[1].parejaId, 'p1');
      expect(posiciones[2].parejaId, 'p2');
      expect(posiciones[0].partidosGanados, 2);
    });
  });
}
