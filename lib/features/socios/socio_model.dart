import 'package:cloud_firestore/cloud_firestore.dart';

/// Compara sólo el día calendario (año/mes/día), no el instante exacto.
///
/// 🚨 Antes varias pantallas hacían `vencimiento.isAfter(DateTime.now())`
/// directo: si el Apto Médico vence el 16/11, eso da `false` ya desde la
/// medianoche del propio 16/11 (00:00 del 16 no es "después" de las 14:30
/// del 16) — el socio quedaba bloqueado en control de acceso un día ANTES
/// de que el vencimiento realmente ocurriera. Ahora la vigencia se evalúa
/// por día completo: sigue vigente durante todo el día de vencimiento y
/// recién se considera vencido al día siguiente.
bool vencimientoVigente(DateTime? vencimiento, [DateTime? ahora]) {
  if (vencimiento == null) return false;
  final hoy = ahora ?? DateTime.now();
  final vencDia = DateTime(vencimiento.year, vencimiento.month, vencimiento.day);
  final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
  return !vencDia.isBefore(hoyDia);
}

/// 🔒 QR Dinámico anti-capturas: valida que el token escaneado del carnet
/// coincida con el vigente en Firestore y que todavía no haya vencido. Se
/// extrae como función pura (en vez de quedar inline en
/// control_acceso_page.dart) para poder testearla sin un widget completo.
bool qrTokenValido(
  Map<String, dynamic> socioData,
  String tokenEscaneado, [
  DateTime? ahora,
]) {
  final String? tokenVigente = socioData['qrTokenActual']?.toString();
  final dynamic expiraRaw = socioData['qrTokenExpira'];
  if (tokenVigente == null || tokenVigente != tokenEscaneado) return false;
  if (expiraRaw == null) return false;
  final DateTime expira = expiraRaw is Timestamp
      ? expiraRaw.toDate()
      : (expiraRaw is DateTime ? expiraRaw : DateTime.fromMillisecondsSinceEpoch(0));
  return expira.isAfter(ahora ?? DateTime.now());
}

/// 🏊 Semáforo sanitario del natatorio: para reservar/usar un andarivel el
/// socio necesita Apto Médico Y revisión de pediculosis/micosis vigentes
/// (requisito sanitario específico de pileta, no aplica a pádel/gimnasio).
bool semaforoSanitarioNatatorioOk(SocioModel socio) {
  return vencimientoVigente(socio.vencimientoAptoMedico) &&
      vencimientoVigente(socio.vencimientoPediculosisMicosis);
}

class SocioModel {
  final String id;
  final String numeroSocio;
  final String nombre;
  final String dni;
  final String telefono;
  final String fotoUrl;
  final String aptoUrl;
  final DateTime fechaAlta;
  final bool activo;

  final DateTime? fechaNacimiento;
  final DateTime? vencimientoAptoMedico;
  final DateTime? vencimientoPediculosisMicosis;
  final String contactoEmergencia;

  final String deporte;
  final String frecuencia;
  final List<String> dias;
  final String idBloqueHorario;
  final double saldoCuentaCorriente;

  // 🏷️ CONTROL DE MATRÍCULA Y LÍNEA TEMPORAL DE PAGOS
  final bool matriculaAlDia;
  final DateTime? fechaPagoMatricula;
  final String ultimoMesPago;
  final String? mesesCubiertosHasta;
  final String huellaHash;
  final List<String>
  huellasHashes; // 👈 HUELLAS MÚLTIPLES (SOCIO / PAPÁ / MAMÁ)

  // 🏫 CONVENIO / ARANCEL ESCOLAR
  final bool esEstudianteEscuela;
  final String? colegioInstitucion;
  final String? gradoAnio;
  final double descuentoEscolarPorcentaje;

  // 👨‍👩‍👧‍👦 GRUPO FAMILIAR (descuento por vínculo con otros socios)
  final String? grupoFamiliarId;

  SocioModel({
    required this.id,
    required this.numeroSocio,
    required this.nombre,
    required this.dni,
    required this.telefono,
    required this.fotoUrl,
    required this.aptoUrl,
    required this.fechaAlta,
    required this.activo,
    this.fechaNacimiento,
    this.vencimientoAptoMedico,
    this.vencimientoPediculosisMicosis,
    required this.contactoEmergencia,
    required this.deporte,
    required this.frecuencia,
    required this.dias,
    required this.idBloqueHorario,
    required this.saldoCuentaCorriente,
    this.matriculaAlDia = false,
    this.fechaPagoMatricula,
    this.ultimoMesPago = 'Sin Registros',
    this.mesesCubiertosHasta,
    this.huellaHash = '',
    this.huellasHashes = const [],
    this.esEstudianteEscuela = false,
    this.colegioInstitucion,
    this.gradoAnio,
    this.descuentoEscolarPorcentaje = 0.0,
    this.grupoFamiliarId,
  });

  factory SocioModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime? parseFecha(dynamic valor) {
      if (valor == null) return null;
      if (valor is Timestamp) return valor.toDate();
      if (valor is String) return DateTime.tryParse(valor);
      return null;
    }

    return SocioModel(
      id: doc.id,
      numeroSocio: data['numeroSocio']?.toString() ?? doc.id,
      nombre: data['nombre']?.toString() ?? '',
      dni: data['dni']?.toString() ?? '',
      telefono: data['telefono']?.toString() ?? '',
      fotoUrl: data['fotoUrl']?.toString() ?? '',
      aptoUrl: data['aptoUrl']?.toString() ?? '',
      fechaAlta: parseFecha(data['fechaAlta']) ?? DateTime.now(),
      activo: data['activo'] == true,
      fechaNacimiento: parseFecha(data['fechaNacimiento']),
      vencimientoAptoMedico: parseFecha(data['vencimientoAptoMedico']),
      vencimientoPediculosisMicosis: parseFecha(
        data['vencimientoPediculosisMicosis'],
      ),
      contactoEmergencia: data['contactoEmergencia']?.toString() ?? '',
      deporte: data['deporte']?.toString() ?? 'Socio Natatorio',
      frecuencia: data['frecuencia']?.toString() ?? '',
      dias: List<String>.from(data['dias'] ?? []),
      idBloqueHorario: data['idBloqueHorario']?.toString() ?? '',
      saldoCuentaCorriente:
          (data['saldoCuentaCorriente'] as num?)?.toDouble() ?? 0.0,
      matriculaAlDia: data['matriculaAlDia'] == true,
      fechaPagoMatricula: parseFecha(data['fechaPagoMatricula']),
      ultimoMesPago: data['ultimoMesPago']?.toString() ?? 'Sin Registros',
      mesesCubiertosHasta: data['mesesCubiertosHasta']?.toString(),
      huellaHash: data['huellaHash']?.toString() ?? '',
      huellasHashes: List<String>.from(data['huellasHashes'] ?? []),
      esEstudianteEscuela: data['esEstudianteEscuela'] == true,
      colegioInstitucion: data['colegioInstitucion']?.toString(),
      gradoAnio: data['gradoAnio']?.toString(),
      descuentoEscolarPorcentaje:
          (data['descuentoEscolarPorcentaje'] as num?)?.toDouble() ?? 0.0,
      grupoFamiliarId: data['grupoFamiliarId']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'numeroSocio': numeroSocio,
      'nombre': nombre,
      'dni': dni,
      'telefono': telefono,
      'fotoUrl': fotoUrl,
      'aptoUrl': aptoUrl,
      'fechaAlta': Timestamp.fromDate(fechaAlta),
      'activo': activo,
      'fechaNacimiento': fechaNacimiento != null
          ? Timestamp.fromDate(fechaNacimiento!)
          : null,
      'vencimientoAptoMedico': vencimientoAptoMedico != null
          ? Timestamp.fromDate(vencimientoAptoMedico!)
          : null,
      'vencimientoPediculosisMicosis': vencimientoPediculosisMicosis != null
          ? Timestamp.fromDate(vencimientoPediculosisMicosis!)
          : null,
      'contactoEmergencia': contactoEmergencia,
      'deporte': deporte,
      'frecuencia': frecuencia,
      'dias': dias,
      'idBloqueHorario': idBloqueHorario,
      'saldoCuentaCorriente': saldoCuentaCorriente,
      'matriculaAlDia': matriculaAlDia,
      'fechaPagoMatricula': fechaPagoMatricula != null
          ? Timestamp.fromDate(fechaPagoMatricula!)
          : null,
      'ultimoMesPago': ultimoMesPago,
      'mesesCubiertosHasta': mesesCubiertosHasta,
      'huellaHash': huellaHash,
      'huellasHashes': huellasHashes,
      'esEstudianteEscuela': esEstudianteEscuela,
      'colegioInstitucion': colegioInstitucion,
      'gradoAnio': gradoAnio,
      'descuentoEscolarPorcentaje': descuentoEscolarPorcentaje,
      'grupoFamiliarId': grupoFamiliarId,
    };
  }
}
