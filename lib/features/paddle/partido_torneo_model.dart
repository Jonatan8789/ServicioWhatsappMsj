import 'package:cloud_firestore/cloud_firestore.dart';

/// Un set jugado dentro de un partido (mejor de 3 sets, habitual en pádel).
class SetJugado {
  final int gamesA;
  final int gamesB;

  const SetJugado({required this.gamesA, required this.gamesB});

  Map<String, dynamic> toMap() => {'gamesA': gamesA, 'gamesB': gamesB};

  factory SetJugado.fromMap(Map<String, dynamic> map) => SetJugado(
    gamesA: (map['gamesA'] as num?)?.toInt() ?? 0,
    gamesB: (map['gamesB'] as num?)?.toInt() ?? 0,
  );
}

/// Un partido del torneo, sea de fase de grupos o de la llave eliminatoria.
///
/// [parejaAId]/[parejaBId] son el ID del documento en
/// torneos/{id}/parejas_inscriptas, o null si el cupo todavía no se definió
/// (partido de una ronda futura, esperando el ganador de rondas previas) o si
/// es un BYE (pasaje directo sin rival).
class PartidoTorneo {
  final String id;
  final String fase; // 'grupos' | 'llave' | 'losers' (doble eliminación)
  final String? grupoNombre; // sólo fase 'grupos', ej. "Zona A"
  final int ronda; // 1-indexado. En grupos: número de fecha/jornada.
  final int ordenEnRonda; // posición dentro de la ronda, define el layout
  final String? parejaAId;
  final String parejaANombre;
  final String? parejaBId;
  final String parejaBNombre;
  final bool esByeA; // parejaA pasa directo (sin rival) en esta ronda
  final bool esByeB;
  final String estado; // 'Pendiente' | 'Jugado'
  final List<SetJugado> sets;
  final String? ganador; // 'A' | 'B' | null
  final String? siguientePartidoId; // a qué partido avanza el ganador
  final String? siguienteSlot; // 'A' | 'B' en ese próximo partido
  // 🚨 Doble eliminación: a qué partido cae el PERDEDOR (null si el formato
  // es eliminación simple, o si ya es la ronda de losers-bracket).
  final String? partidoPerdedorId;
  final String? partidoPerdedorSlot;
  final DateTime? fechaHora;
  final String? cancha;

  const PartidoTorneo({
    required this.id,
    required this.fase,
    this.grupoNombre,
    required this.ronda,
    required this.ordenEnRonda,
    this.parejaAId,
    this.parejaANombre = 'A definir',
    this.parejaBId,
    this.parejaBNombre = 'A definir',
    this.esByeA = false,
    this.esByeB = false,
    this.estado = 'Pendiente',
    this.sets = const [],
    this.ganador,
    this.siguientePartidoId,
    this.siguienteSlot,
    this.partidoPerdedorId,
    this.partidoPerdedorSlot,
    this.fechaHora,
    this.cancha,
  });

  bool get esBye => esByeA || esByeB;
  bool get listoParaJugar =>
      estado == 'Pendiente' &&
      parejaAId != null &&
      parejaBId != null &&
      !esBye;

  int get setsGanadosA => sets.where((s) => s.gamesA > s.gamesB).length;
  int get setsGanadosB => sets.where((s) => s.gamesB > s.gamesA).length;

  Map<String, dynamic> toFirestore() {
    return {
      'fase': fase,
      'grupoNombre': grupoNombre,
      'ronda': ronda,
      'ordenEnRonda': ordenEnRonda,
      'parejaAId': parejaAId,
      'parejaANombre': parejaANombre,
      'parejaBId': parejaBId,
      'parejaBNombre': parejaBNombre,
      'esByeA': esByeA,
      'esByeB': esByeB,
      'estado': estado,
      'sets': sets.map((s) => s.toMap()).toList(),
      'ganador': ganador,
      'siguientePartidoId': siguientePartidoId,
      'siguienteSlot': siguienteSlot,
      'partidoPerdedorId': partidoPerdedorId,
      'partidoPerdedorSlot': partidoPerdedorSlot,
      'fechaHora': fechaHora != null ? Timestamp.fromDate(fechaHora!) : null,
      'cancha': cancha,
    };
  }

  factory PartidoTorneo.fromFirestore(String id, Map<String, dynamic> data) {
    return PartidoTorneo(
      id: id,
      fase: data['fase']?.toString() ?? 'llave',
      grupoNombre: data['grupoNombre']?.toString(),
      ronda: (data['ronda'] as num?)?.toInt() ?? 1,
      ordenEnRonda: (data['ordenEnRonda'] as num?)?.toInt() ?? 0,
      parejaAId: data['parejaAId']?.toString(),
      parejaANombre: data['parejaANombre']?.toString() ?? 'A definir',
      parejaBId: data['parejaBId']?.toString(),
      parejaBNombre: data['parejaBNombre']?.toString() ?? 'A definir',
      esByeA: data['esByeA'] == true,
      esByeB: data['esByeB'] == true,
      estado: data['estado']?.toString() ?? 'Pendiente',
      sets: (data['sets'] as List<dynamic>? ?? [])
          .map((s) => SetJugado.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      ganador: data['ganador']?.toString(),
      siguientePartidoId: data['siguientePartidoId']?.toString(),
      siguienteSlot: data['siguienteSlot']?.toString(),
      partidoPerdedorId: data['partidoPerdedorId']?.toString(),
      partidoPerdedorSlot: data['partidoPerdedorSlot']?.toString(),
      fechaHora: (data['fechaHora'] as Timestamp?)?.toDate(),
      cancha: data['cancha']?.toString(),
    );
  }

  PartidoTorneo copyWith({
    String? parejaAId,
    String? parejaANombre,
    String? parejaBId,
    String? parejaBNombre,
    bool? esByeA,
    bool? esByeB,
    String? estado,
    List<SetJugado>? sets,
    String? ganador,
  }) {
    return PartidoTorneo(
      id: id,
      fase: fase,
      grupoNombre: grupoNombre,
      ronda: ronda,
      ordenEnRonda: ordenEnRonda,
      parejaAId: parejaAId ?? this.parejaAId,
      parejaANombre: parejaANombre ?? this.parejaANombre,
      parejaBId: parejaBId ?? this.parejaBId,
      parejaBNombre: parejaBNombre ?? this.parejaBNombre,
      esByeA: esByeA ?? this.esByeA,
      esByeB: esByeB ?? this.esByeB,
      estado: estado ?? this.estado,
      sets: sets ?? this.sets,
      ganador: ganador ?? this.ganador,
      siguientePartidoId: siguientePartidoId,
      siguienteSlot: siguienteSlot,
      partidoPerdedorId: partidoPerdedorId,
      partidoPerdedorSlot: partidoPerdedorSlot,
      fechaHora: fechaHora,
      cancha: cancha,
    );
  }
}

/// Fila de la tabla de posiciones de una zona/grupo.
class PosicionZona {
  final String parejaId;
  final String parejaNombre;
  int partidosJugados = 0;
  int partidosGanados = 0;
  int setsGanados = 0;
  int setsPerdidos = 0;
  int gamesGanados = 0;
  int gamesPerdidos = 0;

  PosicionZona({required this.parejaId, required this.parejaNombre});

  int get diferenciaSets => setsGanados - setsPerdidos;
  int get diferenciaGames => gamesGanados - gamesPerdidos;
}
