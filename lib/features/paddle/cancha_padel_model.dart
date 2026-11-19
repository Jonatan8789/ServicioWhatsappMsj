/// Configuración de una cancha de pádel en particular (`canchas_padel`).
///
/// Antes sólo existía `configuracion_paddle/canchas` (una lista plana de
/// nombres) y un único doc de precios globales
/// (`configuraciones_paddle/ajustes_globales`) — todas las canchas cobraban
/// exactamente lo mismo. Acá cada cancha puede pisar el precio/horario de
/// luz global si hace falta (ej. la cancha con muro vale distinto que las de
/// cristal); si un campo queda en null, se usa el valor global como
/// fallback.
class CanchaPadelModel {
  final String id;
  final String nombre;
  final String tipoSuperficie;
  final bool activa;
  final bool permiteTurnosFijos;
  final double? precioBaseHoraSocio;
  final double? precioBaseHoraExterno;
  final double? precioAdicionalLuz;
  final int? horaInicioLuz;
  final int ordenVisualizacion;

  const CanchaPadelModel({
    required this.id,
    required this.nombre,
    this.tipoSuperficie = 'Cristal',
    this.activa = true,
    this.permiteTurnosFijos = true,
    this.precioBaseHoraSocio,
    this.precioBaseHoraExterno,
    this.precioAdicionalLuz,
    this.horaInicioLuz,
    this.ordenVisualizacion = 0,
  });

  factory CanchaPadelModel.fromFirestore(String id, Map<String, dynamic> data) {
    return CanchaPadelModel(
      id: id,
      nombre: data['nombre']?.toString() ?? id,
      tipoSuperficie: data['tipoSuperficie']?.toString() ?? 'Cristal',
      activa: data['activa'] as bool? ?? true,
      permiteTurnosFijos: data['permiteTurnosFijos'] as bool? ?? true,
      precioBaseHoraSocio: (data['precioBaseHoraSocio'] as num?)?.toDouble(),
      precioBaseHoraExterno: (data['precioBaseHoraExterno'] as num?)
          ?.toDouble(),
      precioAdicionalLuz: (data['precioAdicionalLuz'] as num?)?.toDouble(),
      horaInicioLuz: (data['horaInicioLuz'] as num?)?.toInt(),
      ordenVisualizacion: (data['ordenVisualizacion'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'tipoSuperficie': tipoSuperficie,
      'activa': activa,
      'permiteTurnosFijos': permiteTurnosFijos,
      'precioBaseHoraSocio': precioBaseHoraSocio,
      'precioBaseHoraExterno': precioBaseHoraExterno,
      'precioAdicionalLuz': precioAdicionalLuz,
      'horaInicioLuz': horaInicioLuz,
      'ordenVisualizacion': ordenVisualizacion,
    };
  }
}
