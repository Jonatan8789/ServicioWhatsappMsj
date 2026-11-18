import 'package:cloud_firestore/cloud_firestore.dart';

/// Motor de puntuación de pádel: toda la lógica vive en funciones estáticas
/// que transforman el mapa de estado del partido (la misma forma que se
/// guarda en Firestore en `partidos_marcador/{idCancha}`), para poder
/// aplicarla desde cualquier pantalla (mando auxiliar, futuros atajos, etc.)
/// sin depender de un StatefulWidget particular.
class PadelScoreEngine {
  static const String modoPuntoDeOro = 'puntoDeOro';
  static const String modoVentaja = 'ventaja';

  static const int _historialMaximo = 30;

  /// Convierte el nombre visible de una cancha ("Cancha 1 Cristal") en un ID
  /// de documento válido para `partidos_marcador` ("cancha_1_cristal").
  static String idDocumentoDesdeCancha(String nombreCancha) {
    const conAcentos = 'áéíóúÁÉÍÓÚñÑ';
    const sinAcentos = 'aeiouAEIOUnN';

    String normalizado = nombreCancha;
    for (int i = 0; i < conAcentos.length; i++) {
      normalizado = normalizado.replaceAll(conAcentos[i], sinAcentos[i]);
    }

    normalizado = normalizado
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    return normalizado.isEmpty ? 'cancha' : normalizado;
  }

  /// Arma el estado inicial de un partido nuevo, listo para escribirse en
  /// `partidos_marcador/{idCancha}`.
  static Map<String, dynamic> estadoInicial({
    required String cancha,
    required Map<String, dynamic> equipoA,
    required Map<String, dynamic> equipoB,
    String modoJuego = modoPuntoDeOro,
    int cantidadSets = 3,
    String saqueInicial = 'A',
  }) {
    return {
      'cancha': cancha,
      'activo': true,
      'equipoA': equipoA,
      'equipoB': equipoB,
      'modoJuego': modoJuego,
      'cantidadSets': cantidadSets,
      'saque': saqueInicial,
      'puntosA': 0,
      'puntosB': 0,
      'enTiebreak': false,
      'puntosTiebreakA': 0,
      'puntosTiebreakB': 0,
      'gamesA': 0,
      'gamesB': 0,
      'setsCompletados': <Map<String, dynamic>>[],
      'setsGanadosA': 0,
      'setsGanadosB': 0,
      'partidoFinalizado': false,
      'ganadorPartido': null,
      'historial': <Map<String, dynamic>>[],
      'fechaInicio': FieldValue.serverTimestamp(),
      'ultimaActualizacion': FieldValue.serverTimestamp(),
    };
  }

  /// Devuelve la etiqueta visible del punto actual ('0', '15', '30', '40',
  /// 'AD' o '40 Igual' según corresponda).
  static String etiquetaPunto({
    required int puntos,
    required int puntosRival,
    required String modoJuego,
  }) {
    const nombres = ['0', '15', '30', '40'];

    if (puntos < 3 && puntosRival < 3) {
      return nombres[puntos];
    }
    if (puntos < 3) return nombres[puntos];

    // A partir de acá ambos equipos están en 40 o por encima (deuce/ventaja).
    if (modoJuego == modoPuntoDeOro) {
      // Punto de oro: nunca hay ventaja, el marcador se queda clavado en 40.
      return '40';
    }

    final diferencia = puntos - puntosRival;
    if (diferencia == 0) return '40';
    if (diferencia > 0) return 'AD';
    return '40';
  }

  /// Suma un punto al [equipo] ('A' o 'B'), aplicando las reglas de juego,
  /// set y partido. Antes de mutar nada apila una foto del estado actual en
  /// `historial` para poder deshacer con [deshacerPunto].
  static Map<String, dynamic> sumarPunto(
    Map<String, dynamic> estadoActual,
    String equipo,
  ) {
    if (estadoActual['partidoFinalizado'] == true) return estadoActual;

    final estado = _clonarProfundo(estadoActual);
    _apilarHistorial(estado, estadoActual);

    final bool esA = equipo == 'A';
    final bool enTiebreak = estado['enTiebreak'] == true;

    if (enTiebreak) {
      _sumarPuntoTiebreak(estado, esA);
    } else {
      _sumarPuntoGame(estado, esA);
    }

    estado['ultimaActualizacion'] = FieldValue.serverTimestamp();
    return estado;
  }

  static void _sumarPuntoGame(Map<String, dynamic> estado, bool esA) {
    final String modoJuego = estado['modoJuego']?.toString() ?? modoPuntoDeOro;
    int puntosA = (estado['puntosA'] as num?)?.toInt() ?? 0;
    int puntosB = (estado['puntosB'] as num?)?.toInt() ?? 0;

    int puntosGanador = esA ? puntosA : puntosB;
    int puntosPerdedor = esA ? puntosB : puntosA;

    bool ganaElGame;
    if (puntosGanador < 3) {
      // 0 -> 15 -> 30 -> 40: todavía no se define nada.
      puntosGanador += 1;
      ganaElGame = false;
    } else if (puntosPerdedor < 3) {
      // Tiene 40 y el rival no llegó a 40: gana el game directo.
      ganaElGame = true;
    } else {
      // Deuce (40 iguales) o ya hay ventaja.
      final diferencia = puntosGanador - puntosPerdedor;
      if (modoJuego == modoPuntoDeOro) {
        // Punto de oro: con 40 iguales, el próximo punto define el game.
        ganaElGame = diferencia >= 0;
      } else {
        if (diferencia < 0) {
          // El rival tenía la ventaja: vuelve a deuce (40 iguales).
          puntosGanador = 3;
          puntosPerdedor = 3;
          ganaElGame = false;
        } else if (diferencia == 0) {
          // Estaban en deuce: ahora el ganador pasa a tener ventaja.
          puntosGanador += 1;
          ganaElGame = false;
        } else {
          // Ya tenía la ventaja y vuelve a sumar: gana el game.
          ganaElGame = true;
        }
      }
    }

    if (esA) {
      estado['puntosA'] = ganaElGame ? 0 : puntosGanador;
      estado['puntosB'] = ganaElGame ? 0 : puntosPerdedor;
    } else {
      estado['puntosB'] = ganaElGame ? 0 : puntosGanador;
      estado['puntosA'] = ganaElGame ? 0 : puntosPerdedor;
    }

    if (ganaElGame) {
      _sumarGame(estado, esA);
    }
  }

  static void _sumarGame(Map<String, dynamic> estado, bool esA) {
    estado['puntosA'] = 0;
    estado['puntosB'] = 0;

    int gamesA = (estado['gamesA'] as num?)?.toInt() ?? 0;
    int gamesB = (estado['gamesB'] as num?)?.toInt() ?? 0;
    if (esA) {
      gamesA += 1;
    } else {
      gamesB += 1;
    }
    estado['gamesA'] = gamesA;
    estado['gamesB'] = gamesB;

    _alternarSaqueInterno(estado);

    // 6-6: va a tie-break en vez de definir el set directo.
    if (gamesA == 6 && gamesB == 6) {
      estado['enTiebreak'] = true;
      estado['puntosTiebreakA'] = 0;
      estado['puntosTiebreakB'] = 0;
      return;
    }

    final bool seDefinioElSet =
        (gamesA >= 6 || gamesB >= 6) && (gamesA - gamesB).abs() >= 2;
    if (seDefinioElSet) {
      _cerrarSet(estado, gamesA, gamesB);
    }
  }

  static void _sumarPuntoTiebreak(Map<String, dynamic> estado, bool esA) {
    int ptA = (estado['puntosTiebreakA'] as num?)?.toInt() ?? 0;
    int ptB = (estado['puntosTiebreakB'] as num?)?.toInt() ?? 0;

    if (esA) {
      ptA += 1;
    } else {
      ptB += 1;
    }
    estado['puntosTiebreakA'] = ptA;
    estado['puntosTiebreakB'] = ptB;

    // Real cada 2 puntos jugados (impar en la suma total), salvo el primero.
    final int totalPuntos = ptA + ptB;
    if (totalPuntos == 1 || (totalPuntos > 1 && totalPuntos.isOdd)) {
      _alternarSaqueInterno(estado);
    }

    final bool ganaTiebreakA =
        ptA >= 7 && (ptA - ptB) >= 2;
    final bool ganaTiebreakB =
        ptB >= 7 && (ptB - ptA) >= 2;

    if (ganaTiebreakA || ganaTiebreakB) {
      int gamesA = (estado['gamesA'] as num?)?.toInt() ?? 0;
      int gamesB = (estado['gamesB'] as num?)?.toInt() ?? 0;
      if (ganaTiebreakA) {
        gamesA += 1;
      } else {
        gamesB += 1;
      }
      estado['enTiebreak'] = false;
      estado['puntosTiebreakA'] = 0;
      estado['puntosTiebreakB'] = 0;
      _cerrarSet(estado, gamesA, gamesB);
    }
  }

  static void _cerrarSet(Map<String, dynamic> estado, int gamesA, int gamesB) {
    final List<Map<String, dynamic>> sets = _listaSets(estado);
    sets.add({'a': gamesA, 'b': gamesB});
    estado['setsCompletados'] = sets;

    estado['gamesA'] = 0;
    estado['gamesB'] = 0;

    final bool ganoA = gamesA > gamesB;
    int setsGanadosA = (estado['setsGanadosA'] as num?)?.toInt() ?? 0;
    int setsGanadosB = (estado['setsGanadosB'] as num?)?.toInt() ?? 0;
    if (ganoA) {
      setsGanadosA += 1;
    } else {
      setsGanadosB += 1;
    }
    estado['setsGanadosA'] = setsGanadosA;
    estado['setsGanadosB'] = setsGanadosB;

    final int cantidadSets = (estado['cantidadSets'] as num?)?.toInt() ?? 3;
    final int setsParaGanar = (cantidadSets / 2).ceil();

    if (setsGanadosA >= setsParaGanar || setsGanadosB >= setsParaGanar) {
      estado['partidoFinalizado'] = true;
      estado['ganadorPartido'] = setsGanadosA >= setsParaGanar ? 'A' : 'B';
    }
  }

  /// Deshace el último punto cargado, restaurando la foto previa guardada en
  /// `historial`. Si no hay historial (nada para deshacer) devuelve el mismo
  /// estado sin cambios.
  static Map<String, dynamic> deshacerPunto(Map<String, dynamic> estadoActual) {
    final historial = _listaHistorial(estadoActual);
    if (historial.isEmpty) return estadoActual;

    final anterior = _clonarProfundo(historial.removeLast());
    anterior['historial'] = historial;
    anterior['ultimaActualizacion'] = FieldValue.serverTimestamp();
    return anterior;
  }

  /// Invierte quién tiene el saque, sin tocar el resto del marcador. Útil
  /// como corrección manual desde el mando auxiliar.
  static Map<String, dynamic> alternarSaque(Map<String, dynamic> estadoActual) {
    final estado = _clonarProfundo(estadoActual);
    _alternarSaqueInterno(estado);
    estado['ultimaActualizacion'] = FieldValue.serverTimestamp();
    return estado;
  }

  static void _alternarSaqueInterno(Map<String, dynamic> estado) {
    estado['saque'] = estado['saque'] == 'A' ? 'B' : 'A';
  }

  static void _apilarHistorial(
    Map<String, dynamic> estadoNuevo,
    Map<String, dynamic> estadoPrevio,
  ) {
    final historial = _listaHistorial(estadoNuevo);
    final foto = _clonarProfundo(estadoPrevio);
    foto.remove('historial');
    historial.add(foto);
    if (historial.length > _historialMaximo) {
      historial.removeAt(0);
    }
    estadoNuevo['historial'] = historial;
  }

  static List<Map<String, dynamic>> _listaSets(Map<String, dynamic> estado) {
    final raw = estado['setsCompletados'] as List<dynamic>? ?? [];
    return raw.map((s) => Map<String, dynamic>.from(s as Map)).toList();
  }

  static List<Map<String, dynamic>> _listaHistorial(
    Map<String, dynamic> estado,
  ) {
    final raw = estado['historial'] as List<dynamic>? ?? [];
    return raw.map((s) => Map<String, dynamic>.from(s as Map)).toList();
  }

  /// Clon profundo liviano (sólo Map/List/valores primitivos), suficiente
  /// para los documentos de marcador: evita que dos estados compartan la
  /// misma instancia mutable de listas/mapas anidados.
  static Map<String, dynamic> _clonarProfundo(Map<String, dynamic> origen) {
    return Map<String, dynamic>.from(
      origen.map((key, value) => MapEntry(key, _clonarValor(value))),
    );
  }

  static dynamic _clonarValor(dynamic valor) {
    if (valor is Map) {
      return Map<String, dynamic>.from(
        valor.map((k, v) => MapEntry(k.toString(), _clonarValor(v))),
      );
    }
    if (valor is List) {
      return valor.map(_clonarValor).toList();
    }
    return valor;
  }
}
