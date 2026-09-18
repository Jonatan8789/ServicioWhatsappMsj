import 'package:cloud_firestore/cloud_firestore.dart';
import 'bracket_generator_service.dart';
import 'partido_torneo_model.dart';

/// Escribe en Firestore lo que BracketGeneratorService arma en memoria, y
/// maneja el ciclo de vida de un torneo: sortear, cargar resultados
/// (propagando el ganador al próximo partido de la llave), y pasar de fase
/// de grupos a la llave eliminatoria usando las posiciones reales.
class TorneoFirestoreService {
  TorneoFirestoreService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _partidosRef(
    String torneoId,
  ) => _db.collection('torneos').doc(torneoId).collection('partidos');

  static Future<void> generarSorteoEliminacionSimple({
    required String torneoId,
    required List<ParejaSeed> parejasSembradas,
  }) async {
    final partidos = BracketGeneratorService.generarEliminacionSimple(
      parejasSembradas,
    );
    if (partidos.isEmpty) {
      throw Exception('Hacen falta al menos 2 parejas para sortear la llave.');
    }

    final batch = _db.batch();
    for (final p in partidos) {
      batch.set(_partidosRef(torneoId).doc(p.id), p.toFirestore());
    }
    batch.update(_db.collection('torneos').doc(torneoId), {
      'faseActual': 'llave',
      'estado': 'en_curso',
      'formato': 'Eliminación Simple',
      'fechaSorteo': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> generarFaseDeGrupos({
    required String torneoId,
    required List<ParejaSeed> parejasSembradas,
    required int cantidadGrupos,
  }) async {
    if (parejasSembradas.length < cantidadGrupos * 2) {
      throw Exception(
        'Hacen falta al menos ${cantidadGrupos * 2} parejas para $cantidadGrupos zonas.',
      );
    }

    final grupos = BracketGeneratorService.distribuirEnGrupos(
      parejasSembradas,
      cantidadGrupos,
    );

    final batch = _db.batch();
    for (final entry in grupos.entries) {
      final partidosZona = BracketGeneratorService.generarRoundRobinZona(
        entry.key,
        entry.value,
      );
      for (final p in partidosZona) {
        batch.set(_partidosRef(torneoId).doc(p.id), p.toFirestore());
      }
    }

    // Se guarda qué parejas integran cada zona directamente en el torneo
    // (lista chica, se lee siempre junto con la config del torneo) para no
    // tener que re-derivarla de los partidos al calcular posiciones.
    final gruposParaGuardar = {
      for (final e in grupos.entries)
        e.key: e.value.map((p) => {'id': p.id, 'nombre': p.nombre}).toList(),
    };

    batch.update(_db.collection('torneos').doc(torneoId), {
      'faseActual': 'grupos',
      'estado': 'en_curso',
      'formato': 'Fase de Grupos + Eliminación',
      'cantidadGrupos': cantidadGrupos,
      'grupos': gruposParaGuardar,
      'fechaSorteo': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Arma la llave eliminatoria a partir de las posiciones finales de cada
  /// zona. Los clasificados se intercalan por zona y, dentro de cada
  /// "escalón" (todos los 1°, luego todos los 2°, ...), se alterna el
  /// sentido de recorrido de las zonas — así el 1° de una zona no cae contra
  /// el 2° de esa misma zona en la primera ronda salvo que sea inevitable.
  static Future<void> generarLlaveDesdeGrupos({
    required String torneoId,
    required int clasificadosPorGrupo,
  }) async {
    final torneoDoc = await _db.collection('torneos').doc(torneoId).get();
    final torneoData = torneoDoc.data();
    if (torneoData == null || torneoData['grupos'] == null) {
      throw Exception('Este torneo no tiene fase de grupos configurada.');
    }

    final Map<String, dynamic> gruposRaw = Map<String, dynamic>.from(
      torneoData['grupos'],
    );
    final nombresGrupos = gruposRaw.keys.toList()..sort();

    final partidosSnap = await _partidosRef(
      torneoId,
    ).where('fase', isEqualTo: 'grupos').get();
    final todosLosPartidos = partidosSnap.docs
        .map((d) => PartidoTorneo.fromFirestore(d.id, d.data()))
        .toList();

    final Map<String, List<PosicionZona>> posicionesPorGrupo = {};
    for (final nombreGrupo in nombresGrupos) {
      final parejasDelGrupo = (gruposRaw[nombreGrupo] as List<dynamic>)
          .map(
            (p) => ParejaSeed(
              id: p['id'] as String,
              nombre: p['nombre'] as String,
            ),
          )
          .toList();
      final partidosDelGrupo = todosLosPartidos
          .where((p) => p.grupoNombre == nombreGrupo)
          .toList();
      posicionesPorGrupo[nombreGrupo] = BracketGeneratorService.calcularPosiciones(
        parejasDelGrupo,
        partidosDelGrupo,
      );
    }

    final incompletos = todosLosPartidos.where((p) => p.estado != 'Jugado');
    if (incompletos.isNotEmpty) {
      throw Exception(
        'Todavía hay ${incompletos.length} partido(s) de grupos sin cargar.',
      );
    }

    final List<ParejaSeed> clasificados = [];
    for (int posicion = 0; posicion < clasificadosPorGrupo; posicion++) {
      final ordenGrupos = posicion.isEven
          ? nombresGrupos
          : nombresGrupos.reversed.toList();
      for (final nombreGrupo in ordenGrupos) {
        final tabla = posicionesPorGrupo[nombreGrupo]!;
        if (posicion < tabla.length) {
          final pos = tabla[posicion];
          clasificados.add(
            ParejaSeed(id: pos.parejaId, nombre: pos.parejaNombre),
          );
        }
      }
    }

    final partidosLlave = BracketGeneratorService.generarEliminacionSimple(
      clasificados,
      prefijoId: 'b',
    );

    final batch = _db.batch();
    for (final p in partidosLlave) {
      batch.set(_partidosRef(torneoId).doc(p.id), p.toFirestore());
    }
    batch.update(_db.collection('torneos').doc(torneoId), {
      'faseActual': 'llave',
    });
    await batch.commit();
  }

  /// Carga el resultado de un partido y, si corresponde, propaga el ganador
  /// al próximo partido de la llave. Todo en una transacción para que dos
  /// resultados cargados casi al mismo tiempo (dos canchas distintas) no
  /// puedan pisarse.
  static Future<void> registrarResultado({
    required String torneoId,
    required PartidoTorneo partido,
    required List<SetJugado> sets,
  }) async {
    final setsGanadosA = sets.where((s) => s.gamesA > s.gamesB).length;
    final setsGanadosB = sets.where((s) => s.gamesB > s.gamesA).length;
    if (setsGanadosA == setsGanadosB) {
      throw Exception('El resultado no define un ganador (empate en sets).');
    }
    final ganador = setsGanadosA > setsGanadosB ? 'A' : 'B';

    final ref = _partidosRef(torneoId);

    await _db.runTransaction((tx) async {
      tx.update(ref.doc(partido.id), {
        'estado': 'Jugado',
        'sets': sets.map((s) => s.toMap()).toList(),
        'ganador': ganador,
      });

      if (partido.siguientePartidoId != null && partido.siguienteSlot != null) {
        final idGanador = ganador == 'A' ? partido.parejaAId : partido.parejaBId;
        final nombreGanador = ganador == 'A'
            ? partido.parejaANombre
            : partido.parejaBNombre;
        final campoId = partido.siguienteSlot == 'A'
            ? 'parejaAId'
            : 'parejaBId';
        final campoNombre = partido.siguienteSlot == 'A'
            ? 'parejaANombre'
            : 'parejaBNombre';
        tx.update(ref.doc(partido.siguientePartidoId), {
          campoId: idGanador,
          campoNombre: nombreGanador,
        });
      }
    });

    // Si el partido cargado era el último de la llave (la final), marca el
    // torneo como finalizado.
    if (partido.fase == 'llave' && partido.siguientePartidoId == null) {
      await _db.collection('torneos').doc(torneoId).update({
        'estado': 'finalizado',
        'faseActual': 'finalizado',
      });
    }
  }

  /// Deshace un resultado ya cargado (por si el operador se equivocó al
  /// tipear el marcador) — limpia el partido y, si ya había propagado un
  /// ganador a la siguiente ronda, también limpia ese cupo (siempre que la
  /// siguiente ronda todavía no se haya jugado).
  static Future<void> deshacerResultado({
    required String torneoId,
    required PartidoTorneo partido,
  }) async {
    final ref = _partidosRef(torneoId);
    await _db.runTransaction((tx) async {
      tx.update(ref.doc(partido.id), {
        'estado': 'Pendiente',
        'sets': [],
        'ganador': null,
      });

      if (partido.siguientePartidoId != null && partido.siguienteSlot != null) {
        final siguienteSnap = await tx.get(ref.doc(partido.siguientePartidoId));
        if (siguienteSnap.exists &&
            siguienteSnap.data()?['estado'] != 'Jugado') {
          final campoId = partido.siguienteSlot == 'A'
              ? 'parejaAId'
              : 'parejaBId';
          final campoNombre = partido.siguienteSlot == 'A'
              ? 'parejaANombre'
              : 'parejaBNombre';
          tx.update(ref.doc(partido.siguientePartidoId), {
            campoId: null,
            campoNombre: 'A definir',
          });
        }
      }
    });
  }
}
