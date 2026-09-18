import 'package:cloud_firestore/cloud_firestore.dart';

/// Genera los registros de horas trabajadas que consume
/// liquidacion_profesores_page.dart (colección 'registro_horas_profes').
///
/// Antes esa colección no tenía ningún escritor: el pago de profesores se
/// basa en asistencia real (Entrada/Salida), así que este servicio se llama
/// desde cada lugar que registra una Salida (control_acceso_page.dart,
/// nomina_diaria_page.dart, y el ajuste manual de
/// reporte_horas_profesores_page.dart) para persistir esa sesión trabajada
/// apenas se cierra, en vez de recalcularla cada vez desde 'asistencia'.
class RegistroHorasProfesoresService {
  /// Si se pasa [idRegistro] (pensado como el ID del documento de Salida en
  /// 'asistencia'), la escritura es idempotente: si ya existe un registro
  /// para esa sesión no se vuelve a crear. Esto permite que un backfill
  /// histórico se pueda re-ejecutar sin duplicar horas ni, peor, resetear a
  /// 'liquidado: false' una sesión que ya se había pagado.
  static Future<void> registrarSesionTrabajada({
    required String profesorId,
    required String nombreProfesor,
    required DateTime horaEntrada,
    required DateTime horaSalida,
    String actividad = '',
    String? idRegistro,
  }) async {
    final double cantidadHoras =
        horaSalida.difference(horaEntrada).inMinutes / 60.0;
    if (cantidadHoras <= 0) return;

    final data = {
      'profesorId': profesorId,
      'nombreProfesor': nombreProfesor,
      'actividad': actividad.isNotEmpty ? actividad : 'Natatorio',
      'cantidadHoras': cantidadHoras,
      'fecha': Timestamp.fromDate(horaSalida),
      'liquidado': false,
      'origen': 'ASISTENCIA',
    };

    final firestore = FirebaseFirestore.instance;
    if (idRegistro != null) {
      final ref = firestore.collection('registro_horas_profes').doc(idRegistro);
      final existente = await ref.get();
      if (existente.exists) return;
      await ref.set(data);
    } else {
      await firestore.collection('registro_horas_profes').add(data);
    }
  }
}
