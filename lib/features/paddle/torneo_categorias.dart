/// Categorías de pádel usadas en todo el módulo de torneos, ordenadas de
/// mejor a peor nivel. Antes crear_torneo_page.dart usaba '7ta' mientras que
/// inscripcion_torneo_dialog.dart usaba '7ma' para la misma categoría — un
/// torneo creado como '7ta' nunca podía coincidir con jugadores auto-cargados
/// con categoriaPaddle '7ma'. Se unifica acá en una sola fuente de verdad.
class TorneoCategorias {
  TorneoCategorias._();

  static const List<String> lista = [
    '1ra',
    '2da',
    '3ra',
    '4ta',
    '5ta',
    '6ta',
    '7ma',
    'Principiantes',
  ];

  static const List<String> ramas = ['Caballeros', 'Damas', 'Mixto'];

  static const List<int> cuposDisponibles = [4, 8, 16, 32];

  static const List<String> formatos = [
    'Eliminación Simple',
    'Eliminación Doble',
    'Fase de Grupos + Eliminación',
  ];

  /// Índice de nivel (0 = mejor nivel). Categorías desconocidas devuelven
  /// null (no se puede comparar contra el filtro del torneo).
  static int? nivel(String? categoria) {
    if (categoria == null) return null;
    final i = lista.indexOf(categoria);
    return i == -1 ? null : i;
  }

  /// true si [categoriaJugador] es de mejor nivel que [categoriaTorneo]
  /// (p.ej. un jugador de 3ra anotándose en un torneo de 5ta) — la validación
  /// que pide el negocio para evitar "sandbagging" (jugar en una categoría
  /// inferior a la real para tener más chances de ganar).
  static bool esNivelSuperior(String? categoriaJugador, String categoriaTorneo) {
    final nivelJugador = nivel(categoriaJugador);
    final nivelTorneo = nivel(categoriaTorneo);
    if (nivelJugador == null || nivelTorneo == null) return false;
    return nivelJugador < nivelTorneo;
  }
}
