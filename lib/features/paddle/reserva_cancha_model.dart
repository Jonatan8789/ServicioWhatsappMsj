import 'package:cloud_firestore/cloud_firestore.dart';
import 'item_pro_shop_venta.dart';

class ReservaCanchaModel {
  final String id;
  final String cancha;
  final String nombreCliente;
  final String? socioId;
  final DateTime fecha;
  final int horaInicio;
  final int duracionHoras;
  final double precio;
  final String metodoPago;
  final String estadoReserva;
  // 🚨 Antes el modelo no incluía estos dos campos en el round-trip: se
  // guardaban bien en Firestore (canchas_page.dart) pero cualquier código
  // que pasara por fromFirestore()/toFirestore() los perdía, así que la UI
  // de seña nunca los veía.
  final double senaAbonada;
  final String detalleSena;
  // 🎾 Paletas/pelotas vendidas junto con esta reserva (Pro-Shop real,
  // conectado al stock de inventario_general) — antes era un cargo fijo por
  // hora sin relación con ningún stock.
  final List<ItemProShopVenta> itemsProShop;

  ReservaCanchaModel({
    required this.id,
    required this.cancha,
    required this.nombreCliente,
    this.socioId,
    required this.fecha,
    required this.horaInicio,
    required this.duracionHoras,
    required this.precio,
    required this.metodoPago,
    this.estadoReserva = 'Confirmada',
    this.senaAbonada = 0.0,
    this.detalleSena = '',
    this.itemsProShop = const [],
  });

  Map<String, dynamic> toFirestore() {
    return {
      'cancha': cancha,
      'nombreCliente': nombreCliente,
      'socioId': socioId,
      'fecha': Timestamp.fromDate(fecha),
      'horaInicio': horaInicio,
      'duracionHoras': duracionHoras,
      'precio': precio,
      'metodoPago': metodoPago,
      'estadoReserva': estadoReserva,
      'senaAbonada': senaAbonada,
      'detalleSena': detalleSena,
      'itemsProShop': itemsProShop.map((i) => i.toMap()).toList(),
    };
  }

  factory ReservaCanchaModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return ReservaCanchaModel(
      id: id,
      cancha: data['cancha']?.toString() ?? '',
      nombreCliente: data['nombreCliente']?.toString() ?? '',
      socioId: data['socioId']?.toString(),
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      horaInicio: (data['horaInicio'] as num?)?.toInt() ?? 0,
      duracionHoras: (data['duracionHoras'] as num?)?.toInt() ?? 0,
      precio: (data['precio'] as num?)?.toDouble() ?? 0.0,
      metodoPago: data['metodoPago']?.toString() ?? 'Efectivo',
      estadoReserva: data['estadoReserva']?.toString() ?? 'Confirmada',
      // 🔁 Fallback a las claves viejas con ñ (seña_abonada/detalle_seña):
      // documentos creados antes de esta migración todavía las tienen, y
      // canchas_page.dart necesita seguir mostrando esa seña ya cargada.
      senaAbonada:
          (data['senaAbonada'] as num?)?.toDouble() ??
          (data['seña_abonada'] as num?)?.toDouble() ??
          0.0,
      detalleSena:
          data['detalleSena']?.toString() ??
          data['detalle_seña']?.toString() ??
          '',
      itemsProShop:
          (data['itemsProShop'] as List<dynamic>?)
              ?.map((m) => ItemProShopVenta.fromMap(m as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
