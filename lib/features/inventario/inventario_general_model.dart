import 'package:cloud_firestore/cloud_firestore.dart';

class ComponenteComboGeneral {
  final String itemInventarioId;
  final int cantidad;

  ComponenteComboGeneral({
    required this.itemInventarioId,
    required this.cantidad,
  });

  factory ComponenteComboGeneral.fromMap(Map<String, dynamic> map) {
    return ComponenteComboGeneral(
      itemInventarioId: map['itemInventarioId'] ?? '',
      cantidad: (map['cantidad'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {'itemInventarioId': itemInventarioId, 'cantidad': cantidad};
  }
}

class InventarioGeneralModel {
  final String id;
  final String nombre;
  final String descripcion;
  final String categoria; // Ej: Gaseosas, Paletas, Remeras, Limpieza
  final String
  tipoInventario; // Ej: 'Buffet', 'Pro-Shop', 'Insumos / Mantenimiento'
  final String
  ubicacion; // Ej: 'Depósito Central', 'Barra Buffet', 'Mostrador Recepción'
  final double precioVenta; // PVP al público (0 si es de uso interno)
  final double precioCosto; // Costo de reposición para calcular el Margen Neto
  final int stockActual;
  final int stockMinimo;
  final String codigoBarras;
  final String codigoInterno;
  final String? proveedorId;
  final bool disponible;
  final bool esCombo;
  final List<ComponenteComboGeneral> componentes;
  final bool requiereCocina;

  InventarioGeneralModel({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.categoria,
    required this.tipoInventario,
    required this.ubicacion,
    required this.precioVenta,
    required this.precioCosto,
    required this.stockActual,
    required this.stockMinimo,
    required this.codigoBarras,
    required this.codigoInterno,
    this.proveedorId,
    required this.disponible,
    required this.esCombo,
    required this.componentes,
    required this.requiereCocina,
  });

  factory InventarioGeneralModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return InventarioGeneralModel(
      id: doc.id,
      nombre: data['nombre'] ?? '',
      descripcion: data['descripcion'] ?? '',
      categoria: data['categoria'] ?? 'Varios',
      tipoInventario: data['tipoInventario'] ?? 'Buffet',
      ubicacion: data['ubicacion'] ?? 'Depósito Central',
      precioVenta: (data['precioVenta'] as num?)?.toDouble() ?? 0.0,
      precioCosto: (data['precioCosto'] as num?)?.toDouble() ?? 0.0,
      stockActual: (data['stockActual'] ?? data['stock'] as num?)?.toInt() ?? 0,
      stockMinimo: (data['stockMinimo'] as num?)?.toInt() ?? 5,
      codigoBarras: data['codigoBarras'] ?? '',
      codigoInterno: data['codigoInterno'] ?? '',
      proveedorId: data['proveedorId'],
      disponible: data['disponible'] ?? true,
      esCombo: data['esCombo'] ?? false,
      componentes:
          (data['componentes'] as List<dynamic>?)
              ?.map(
                (item) => ComponenteComboGeneral.fromMap(
                  item as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
      requiereCocina: data['requiereCocina'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'descripcion': descripcion,
      'categoria': categoria,
      'tipoInventario': tipoInventario,
      'ubicacion': ubicacion,
      'precioVenta': precioVenta,
      'precioCosto': precioCosto,
      'stockActual': stockActual,
      'stockMinimo': stockMinimo,
      'codigoBarras': codigoBarras,
      'codigoInterno': codigoInterno,
      'proveedorId': proveedorId,
      'disponible': disponible,
      'esCombo': esCombo,
      'componentes': componentes.map((c) => c.toMap()).toList(),
      'requiereCocina': requiereCocina,
    };
  }
}
