import 'partido_torneo_model.dart';

/// Una pareja ya lista para el sorteo: sólo lo que hace falta para armar la
/// llave (id + nombre para mostrar). El orden de la lista importa: debe venir
/// YA ordenada de mejor semilla a peor (o mezclada al azar si el sorteo es
/// sin ranking) — este servicio no decide el criterio de orden, sólo arma la
/// llave a partir de él.
class ParejaSeed {
  final String id;
  final String nombre;
  const ParejaSeed({required this.id, required this.nombre});
}

/// Arma partidos y calcula posiciones. Es lógica pura (sin Firestore): esto
/// permite verificarla con datos de prueba antes de que una pantalla la
/// use para escribir un torneo real.
class BracketGeneratorService {
  BracketGeneratorService._();

  static int _proximaPotenciaDe2(int n) {
    int p = 1;
    while (p < n) {
      p *= 2;
    }
    return p;
  }

  /// Orden de semillas de bracket estándar (los mejores puestos quedan lo
  /// más separados posible, de forma que sólo se puedan cruzar en instancias
  /// avanzadas). Verificado con casos de prueba antes de integrarlo acá.
  static List<int> _ordenSemillas(int size) {
    if (size == 1) return [0];
    final prev = _ordenSemillas(size ~/ 2);
    final result = <int>[];
    for (final p in prev) {
      result.add(p);
      result.add(size - 1 - p);
    }
    return result;
  }

  /// Llave de eliminación simple completa: todas las rondas, con los BYE de
  /// la primera ronda ya resueltos (el ganador queda cargado directo en la
  /// ronda 2) para que el torneo arranque mostrando sólo los partidos que
  /// realmente hace falta jugar.
  static List<PartidoTorneo> generarEliminacionSimple(
    List<ParejaSeed> parejasSembradas, {
    String prefijoId = 'b',
  }) {
    final n = parejasSembradas.length;
    if (n < 2) return [];

    final tamanioLlave = _proximaPotenciaDe2(n);
    final orden = _ordenSemillas(tamanioLlave);
    final cantidadRondas = tamanioLlave.bitLength - 1;

    final Map<String, PartidoTorneo> porId = {};

    String idDe(int ronda, int m) => '${prefijoId}_r${ronda}_m$m';

    // Ronda 1
    final cantidadR1 = tamanioLlave ~/ 2;
    for (int m = 0; m < cantidadR1; m++) {
      final semillaA = orden[m * 2];
      final semillaB = orden[m * 2 + 1];
      final hayA = semillaA < n;
      final hayB = semillaB < n;
      final esFinal = cantidadRondas == 1;
      porId[idDe(1, m)] = PartidoTorneo(
        id: idDe(1, m),
        fase: 'llave',
        ronda: 1,
        ordenEnRonda: m,
        parejaAId: hayA ? parejasSembradas[semillaA].id : null,
        parejaANombre: hayA ? parejasSembradas[semillaA].nombre : 'BYE',
        parejaBId: hayB ? parejasSembradas[semillaB].id : null,
        parejaBNombre: hayB ? parejasSembradas[semillaB].nombre : 'BYE',
        esByeA: !hayA,
        esByeB: !hayB,
        siguientePartidoId: esFinal ? null : idDe(2, m ~/ 2),
        siguienteSlot: esFinal ? null : (m.isEven ? 'A' : 'B'),
      );
    }

    // Rondas siguientes, vacías (se completan por propagación de ganadores).
    for (int ronda = 2; ronda <= cantidadRondas; ronda++) {
      final cantidad = tamanioLlave ~/ (1 << ronda);
      final esFinal = ronda == cantidadRondas;
      for (int m = 0; m < cantidad; m++) {
        porId[idDe(ronda, m)] = PartidoTorneo(
          id: idDe(ronda, m),
          fase: 'llave',
          ronda: ronda,
          ordenEnRonda: m,
          siguientePartidoId: esFinal ? null : idDe(ronda + 1, m ~/ 2),
          siguienteSlot: esFinal ? null : (m.isEven ? 'A' : 'B'),
        );
      }
    }

    // Resolver BYEs en cascada, ronda por ronda (una ronda sólo puede quedar
    // resuelta-por-bye si la ronda anterior le propagó un único ganador).
    for (int ronda = 1; ronda < cantidadRondas; ronda++) {
      final cantidad = tamanioLlave ~/ (1 << ronda);
      for (int m = 0; m < cantidad; m++) {
        final partido = porId[idDe(ronda, m)]!;
        if (partido.esByeA || partido.esByeB) {
          final ganadorEsA = partido.esByeB; // gana el lado que SÍ tiene pareja
          final idGanador = ganadorEsA ? partido.parejaAId : partido.parejaBId;
          final nombreGanador = ganadorEsA
              ? partido.parejaANombre
              : partido.parejaBNombre;
          porId[partido.id] = partido.copyWith(
            estado: 'Jugado',
            ganador: ganadorEsA ? 'A' : 'B',
          );
          if (partido.siguientePartidoId != null && idGanador != null) {
            final siguiente = porId[partido.siguientePartidoId]!;
            porId[siguiente.id] = partido.siguienteSlot == 'A'
                ? siguiente.copyWith(
                    parejaAId: idGanador,
                    parejaANombre: nombreGanador,
                  )
                : siguiente.copyWith(
                    parejaBId: idGanador,
                    parejaBNombre: nombreGanador,
                  );
          }
        }
      }
    }

    return porId.values.toList();
  }

  /// Distribuye parejas ya sembradas en [cantidadGrupos] zonas usando reparto
  /// "serpiente" (1,2,3,4,4,3,2,1,...) para que cada zona tenga un nivel
  /// parejo en vez de que la Zona A se quede con las 4 mejores parejas.
  static Map<String, List<ParejaSeed>> distribuirEnGrupos(
    List<ParejaSeed> parejasSembradas,
    int cantidadGrupos,
  ) {
    final nombresGrupos = List.generate(
      cantidadGrupos,
      (i) => 'Zona ${String.fromCharCode(65 + i)}',
    );
    final grupos = {for (final n in nombresGrupos) n: <ParejaSeed>[]};

    int i = 0;
    bool derecha = true;
    for (final pareja in parejasSembradas) {
      grupos[nombresGrupos[i]]!.add(pareja);
      if (derecha) {
        if (i == cantidadGrupos - 1) {
          derecha = false;
        } else {
          i++;
        }
      } else {
        if (i == 0) {
          derecha = true;
        } else {
          i--;
        }
      }
    }
    return grupos;
  }

  /// Round-robin (todos contra todos) dentro de una zona, vía método del
  /// círculo — reparte los partidos en jornadas balanceadas.
  static List<PartidoTorneo> generarRoundRobinZona(
    String nombreGrupo,
    List<ParejaSeed> parejas, {
    String prefijoId = 'g',
  }) {
    final n = parejas.length;
    if (n < 2) return [];

    final hayFicticio = n.isOdd;
    final total = hayFicticio ? n + 1 : n;
    final indiceFicticio = n; // sólo válido si hayFicticio
    final fijo = 0;
    var rotando = List<int>.generate(total - 1, (i) => i + 1);

    final partidos = <PartidoTorneo>[];
    int contadorPartido = 0;

    for (int jornada = 0; jornada < total - 1; jornada++) {
      final equiposRonda = [fijo, ...rotando];
      for (int i = 0; i < total ~/ 2; i++) {
        final a = equiposRonda[i];
        final b = equiposRonda[total - 1 - i];
        if (hayFicticio && (a == indiceFicticio || b == indiceFicticio)) {
          continue; // esa pareja libra esta jornada
        }
        partidos.add(
          PartidoTorneo(
            id: '${prefijoId}_${nombreGrupo}_j${jornada + 1}_m$contadorPartido'
                .replaceAll(' ', ''),
            fase: 'grupos',
            grupoNombre: nombreGrupo,
            ronda: jornada + 1,
            ordenEnRonda: contadorPartido,
            parejaAId: parejas[a].id,
            parejaANombre: parejas[a].nombre,
            parejaBId: parejas[b].id,
            parejaBNombre: parejas[b].nombre,
          ),
        );
        contadorPartido++;
      }
      // rotar (método del círculo)
      if (rotando.isNotEmpty) {
        rotando = [rotando.last, ...rotando.sublist(0, rotando.length - 1)];
      }
    }
    return partidos;
  }

  /// Calcula la tabla de posiciones de una zona a partir de sus partidos ya
  /// jugados. Orden: partidos ganados, luego diferencia de sets, luego
  /// diferencia de games (criterio estándar de desempate en pádel/tenis).
  static List<PosicionZona> calcularPosiciones(
    List<ParejaSeed> parejasDelGrupo,
    List<PartidoTorneo> partidosDelGrupo,
  ) {
    final Map<String, PosicionZona> tabla = {
      for (final p in parejasDelGrupo)
        p.id: PosicionZona(parejaId: p.id, parejaNombre: p.nombre),
    };

    for (final partido in partidosDelGrupo) {
      if (partido.estado != 'Jugado' ||
          partido.parejaAId == null ||
          partido.parejaBId == null) {
        continue;
      }
      final posA = tabla[partido.parejaAId];
      final posB = tabla[partido.parejaBId];
      if (posA == null || posB == null) continue;

      posA.partidosJugados++;
      posB.partidosJugados++;

      for (final set in partido.sets) {
        posA.gamesGanados += set.gamesA;
        posA.gamesPerdidos += set.gamesB;
        posB.gamesGanados += set.gamesB;
        posB.gamesPerdidos += set.gamesA;
      }
      posA.setsGanados += partido.setsGanadosA;
      posA.setsPerdidos += partido.setsGanadosB;
      posB.setsGanados += partido.setsGanadosB;
      posB.setsPerdidos += partido.setsGanadosA;

      if (partido.ganador == 'A') {
        posA.partidosGanados++;
      } else if (partido.ganador == 'B') {
        posB.partidosGanados++;
      }
    }

    final lista = tabla.values.toList();
    lista.sort((a, b) {
      if (a.partidosGanados != b.partidosGanados) {
        return b.partidosGanados - a.partidosGanados;
      }
      if (a.diferenciaSets != b.diferenciaSets) {
        return b.diferenciaSets - a.diferenciaSets;
      }
      return b.diferenciaGames - a.diferenciaGames;
    });
    return lista;
  }
}
