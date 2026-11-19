/// Construye el id de documento de una reserva de cancha y los ids de sus
/// slots horarios ocupados.
///
/// Antes esta misma fórmula se repetía a mano en canchas_page.dart,
/// reserva_cancha_screen.dart y reserva_cancha_repository.dart (slots) — y
/// por separado, en el lado de Cloud Functions, en `_idsOcurrenciaCancha`
/// (functions/index.js). El formato tiene que coincidir byte a byte entre
/// Dart y JS para que una reserva creada por el motor de turnos fijos (JS)
/// sea reconocida como "ocupada" por la grilla y por reservarCanchaAtomica
/// (Dart) — si alguna vez se cambia acá, hay que cambiar también
/// `_idsOcurrenciaCancha`/`_fechaIdStrCancha` en functions/index.js.
library;

String fechaIdStrCancha(DateTime fecha) {
  return '${fecha.year}-${fecha.month}-${fecha.day}';
}

String canchaSinEspacios(String cancha) => cancha.replaceAll(' ', '');

String idReservaCancha({
  required DateTime fecha,
  required String cancha,
  required int horaInicio,
  required int duracionHoras,
}) {
  final fechaIdStr = fechaIdStrCancha(fecha);
  final canchaLimpia = canchaSinEspacios(cancha);
  return '${fechaIdStr}_${canchaLimpia}_${horaInicio}hs_duracion${duracionHoras}h';
}

List<String> idsSlotsCancha({
  required DateTime fecha,
  required String cancha,
  required int horaInicio,
  required int duracionHoras,
}) {
  final fechaIdStr = fechaIdStrCancha(fecha);
  final canchaLimpia = canchaSinEspacios(cancha);
  return [
    for (int h = horaInicio; h < horaInicio + duracionHoras; h++)
      '${fechaIdStr}_${canchaLimpia}_${h}hs',
  ];
}
