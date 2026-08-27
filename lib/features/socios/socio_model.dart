import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String contactoEmergencia;

  final String deporte;
  final String frecuencia;
  final List<String> dias;
  final String idBloqueHorario;
  final double saldoCuentaCorriente;

  // 🏷️ CONTROL DE MATRÍCULA Y LÍNEA TEMPORAL DE PAGOS
  final bool matriculaAlDia;
  final DateTime? fechaPagoMatricula;
  final String ultimoMesPago; // Ej: "2026-07" o "Agosto 2026"
  final String? mesesCubiertosHasta; // 👈 NUEVO: "2026-11" para promociones
  final String huellaHash; // 👈 NUEVO: Hash biométrico

  // 🏫 CONVENIO / ARANCEL ESCOLAR
  final bool esEstudianteEscuela;
  final String? colegioInstitucion;
  final String? gradoAnio;
  final double descuentoEscolarPorcentaje;

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
    this.esEstudianteEscuela = false,
    this.colegioInstitucion,
    this.gradoAnio,
    this.descuentoEscolarPorcentaje = 0.0,
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

      esEstudianteEscuela: data['esEstudianteEscuela'] == true,
      colegioInstitucion: data['colegioInstitucion']?.toString(),
      gradoAnio: data['gradoAnio']?.toString(),
      descuentoEscolarPorcentaje:
          (data['descuentoEscolarPorcentaje'] as num?)?.toDouble() ?? 0.0,
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
      'esEstudianteEscuela': esEstudianteEscuela,
      'colegioInstitucion': colegioInstitucion,
      'gradoAnio': gradoAnio,
      'descuentoEscolarPorcentaje': descuentoEscolarPorcentaje,
    };
  }
}
