import 'package:cloud_firestore/cloud_firestore.dart';
import 'registro_horas_profesores_service.dart';

/// Registra el fichaje (Entrada/Salida, alternado) de un profesor. Extraído
/// de control_acceso_page.dart::_ficharProfesor para poder reutilizarlo
/// también desde el autofichaje del portal móvil de profesores
/// (profesor_dashboard_page.dart) sin duplicar la lógica de toggle ni el
/// enganche con RegistroHorasProfesoresService.
class FichajeProfesorService {
  static Future<String> ficharProfesor({
    required String profesorId,
    required String nombreProfesor,
    required String dniProfesor,
    String especialidad = '',
    String modo = 'DOCENTE',
  }) async {
    final firestore = FirebaseFirestore.instance;
    final hoy = DateTime.now();
    final String hoyStr =
        "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}";

    final queryHoy = await firestore
        .collection('asistencia')
        .where('profesorId', isEqualTo: profesorId)
        .where('fechaStr', isEqualTo: hoyStr)
        .get();

    // 🚨 El toggle se decide por el ÚLTIMO fichaje del día (no por "¿existe
    // alguna Entrada hoy?"), y se usa un ID autogenerado en vez de uno
    // determinístico "fecha_profesor_tipo": con el esquema viejo, un 3er/4to
    // fichaje del mismo día volvía a resolver a 'Salida' y su ID coincidía
    // con el de la salida anterior, pisándola silenciosamente.
    String tipoFichaje = 'Entrada';
    DateTime? horaEntradaPrevia;
    if (queryHoy.docs.isNotEmpty) {
      final ultimoRegistro = queryHoy.docs.reduce((a, b) {
        final fechaA =
            (a.data()['fecha'] as Timestamp?)?.toDate() ?? DateTime(0);
        final fechaB =
            (b.data()['fecha'] as Timestamp?)?.toDate() ?? DateTime(0);
        return fechaA.isAfter(fechaB) ? a : b;
      });
      if (ultimoRegistro.data()['tipo'] == 'Entrada') {
        tipoFichaje = 'Salida';
        horaEntradaPrevia = (ultimoRegistro.data()['fecha'] as Timestamp?)
            ?.toDate();
      }
    }

    final DocumentReference refFichaje = await firestore
        .collection('asistencia')
        .add({
          'profesorId': profesorId,
          'nombreProfesor': nombreProfesor,
          'dniProfesor': dniProfesor,
          'fecha': Timestamp.fromDate(hoy),
          'fechaStr': hoyStr,
          'tipo': tipoFichaje,
          'hora':
              "${hoy.hour.toString().padLeft(2, '0')}:${hoy.minute.toString().padLeft(2, '0')}",
        });

    await firestore.collection('asistencias_accesos').add({
      'socioId': profesorId,
      'nombreSocio': nombreProfesor,
      'dniSocio': dniProfesor,
      'tipoEntidad': 'Profesor',
      'fechaHora': Timestamp.fromDate(hoy),
      'fechaStr': hoyStr,
      'modo': modo,
      'tipoFichajeProfe': tipoFichaje,
    });

    if (tipoFichaje == 'Salida' && horaEntradaPrevia != null) {
      await RegistroHorasProfesoresService.registrarSesionTrabajada(
        profesorId: profesorId,
        nombreProfesor: nombreProfesor,
        horaEntrada: horaEntradaPrevia,
        horaSalida: hoy,
        actividad: especialidad,
        idRegistro: refFichaje.id,
      );
    }

    return tipoFichaje;
  }
}
