/// Un ítem de Pro-Shop (paleta, tubo de pelotas, etc.) vendido junto con una
/// reserva de cancha — conecta esa venta al stock real de `inventario_general`
/// (antes era un cargo fijo por hora, desconectado de cualquier stock).
class ItemProShopVenta {
  final String productoId;
  final String nombre;
  final int cantidad;
  final double precioUnitario;

  const ItemProShopVenta({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
  });

  double get subtotal => precioUnitario * cantidad;

  Map<String, dynamic> toMap() {
    return {
      'productoId': productoId,
      'nombre': nombre,
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
    };
  }

  factory ItemProShopVenta.fromMap(Map<String, dynamic> map) {
    return ItemProShopVenta(
      productoId: map['productoId']?.toString() ?? '',
      nombre: map['nombre']?.toString() ?? '',
      cantidad: (map['cantidad'] as num?)?.toInt() ?? 1,
      precioUnitario: (map['precioUnitario'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
