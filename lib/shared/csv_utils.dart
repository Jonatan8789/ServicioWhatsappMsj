/// Codificación CSV mínima (RFC 4180): una celda se entrecomilla si
/// contiene coma, comilla o salto de línea, y las comillas internas se
/// duplican. Es lógica pura para poder testearla sin depender de Firestore
/// ni de plataforma (web/escritorio/móvil).
String celdaCsv(dynamic valor) {
  final texto = valor?.toString() ?? '';
  final necesitaComillas =
      texto.contains(',') || texto.contains('"') || texto.contains('\n');
  if (!necesitaComillas) return texto;
  return '"${texto.replaceAll('"', '""')}"';
}

String filaCsv(List<dynamic> celdas) => celdas.map(celdaCsv).join(',');

/// [encabezados] van primero; cada elemento de [filas] debe tener la misma
/// cantidad de columnas. Usa CRLF (estándar CSV) y antepone un BOM UTF-8
/// para que Excel en Windows no rompa los acentos/ñ al abrirlo.
String generarCsv(List<String> encabezados, List<List<dynamic>> filas) {
  final buffer = StringBuffer('﻿');
  buffer.write(filaCsv(encabezados));
  buffer.write('\r\n');
  for (final fila in filas) {
    buffer.write(filaCsv(fila));
    buffer.write('\r\n');
  }
  return buffer.toString();
}
