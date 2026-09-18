/// Implementación de respaldo para plataformas sin dart:html (móvil/escritorio
/// nativo). La exportación CSV de este módulo está pensada para el panel de
/// administración, que en la práctica corre como app web — en el resto de
/// las plataformas no hay una forma estándar de "descargar un archivo" sin
/// agregar una dependencia nueva (path_provider/share_plus), así que se
/// avisa en vez de fallar en silencio.
Future<void> descargarCsv(String nombreArchivo, String contenidoCsv) async {
  throw UnsupportedError(
    'La exportación a CSV sólo está disponible en la versión web del panel.',
  );
}
