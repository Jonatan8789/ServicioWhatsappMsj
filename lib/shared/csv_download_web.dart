// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

/// Dispara la descarga del CSV en el navegador vía un Blob + <a download>
/// temporal. dart:html está deprecado a favor de package:web, pero sigue
/// siendo el camino más directo y ampliamente soportado en Flutter 3.44
/// para este caso puntual (crear y disparar la descarga de un blob).
Future<void> descargarCsv(String nombreArchivo, String contenidoCsv) async {
  final bytes = utf8.encode(contenidoCsv);
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', nombreArchivo)
    ..click();
  html.Url.revokeObjectUrl(url);
}
