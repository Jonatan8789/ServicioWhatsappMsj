import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natatorio_app/features/paddle/item_pro_shop_venta.dart';
import 'package:natatorio_app/features/paddle/reserva_cancha_model.dart';
import 'package:natatorio_app/features/paddle/reserva_cancha_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ReservaCanchaModel reserva({
    required String id,
    required int horaInicio,
    int duracionHoras = 1,
    String cancha = 'Cancha 1 Cristal',
    List<ItemProShopVenta> itemsProShop = const [],
  }) {
    return ReservaCanchaModel(
      id: id,
      cancha: cancha,
      nombreCliente: 'Socio de prueba',
      fecha: DateTime(2026, 11, 16),
      horaInicio: horaInicio,
      duracionHoras: duracionHoras,
      precio: 4500,
      metodoPago: 'Cuenta Corriente',
      itemsProShop: itemsProShop,
    );
  }

  Future<void> sembrarProductoProShop(
    String id, {
    required int stockActual,
  }) {
    return firestore.collection('inventario_general').doc(id).set({
      'nombre': 'Paleta de prueba',
      'tipoInventario': 'Pro-Shop',
      'precioVenta': 1500.0,
      'precioCosto': 0.0,
      'stockActual': stockActual,
      'stockMinimo': 0,
      'disponible': true,
    });
  }

  group('reservarCanchaAtomica', () {
    test('crea la reserva y sus slots cuando el horario está libre', () async {
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'r1', horaInicio: 10),
      );

      final doc = await firestore.collection('reservas_canchas').doc('r1').get();
      expect(doc.exists, isTrue);

      final slot = await firestore
          .collection('reservas_canchas_slots')
          .doc('2026-11-16_Cancha1Cristal_10hs')
          .get();
      expect(slot.exists, isTrue);
    });

    test(
      'rechaza una segunda reserva con el mismo id exacto (misma cancha/hora/duración) '
      'en vez de pisar silenciosamente a la primera',
      () async {
        await reservarCanchaAtomica(
          firestore: firestore,
          reserva: reserva(id: 'mismo_id', horaInicio: 10),
        );

        expect(
          () => reservarCanchaAtomica(
            firestore: firestore,
            reserva: reserva(id: 'mismo_id', horaInicio: 10),
          ),
          throwsA(isA<HorarioOcupadoException>()),
        );

        // La reserva original sigue intacta: no fue sobreescrita.
        final doc = await firestore
            .collection('reservas_canchas')
            .doc('mismo_id')
            .get();
        expect(doc.data()!['nombreCliente'], 'Socio de prueba');
      },
    );

    test(
      'rechaza una reserva que se solapa parcialmente con otra de distinta duración '
      '(antes esto generaba dos documentos "válidos" para la misma hora)',
      () async {
        // Reserva de 2 horas: ocupa 9 y 10.
        await reservarCanchaAtomica(
          firestore: firestore,
          reserva: reserva(id: 'r_larga', horaInicio: 9, duracionHoras: 2),
        );

        // Otra reserva de 1 hora a las 10 (distinto id, mismo bloque horario real).
        expect(
          () => reservarCanchaAtomica(
            firestore: firestore,
            reserva: reserva(id: 'r_corta', horaInicio: 10),
          ),
          throwsA(isA<HorarioOcupadoException>()),
        );
      },
    );

    test('permite reservar horas distintas en la misma cancha sin conflicto', () async {
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'r_9', horaInicio: 9),
      );
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'r_10', horaInicio: 10),
      );

      final snap = await firestore.collection('reservas_canchas').get();
      expect(snap.docs.length, 2);
    });

    test('permite reservar la misma hora en canchas distintas', () async {
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'cancha1', horaInicio: 10, cancha: 'Cancha 1 Cristal'),
      );
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'cancha2', horaInicio: 10, cancha: 'Cancha 2 Cristal'),
      );

      final snap = await firestore.collection('reservas_canchas').get();
      expect(snap.docs.length, 2);
    });
  });

  group('cancelarReservaCanchaAtomica', () {
    test('libera el horario para que pueda volver a reservarse', () async {
      final r = reserva(id: 'cancelable', horaInicio: 14);
      await reservarCanchaAtomica(firestore: firestore, reserva: r);

      await cancelarReservaCanchaAtomica(firestore: firestore, reserva: r);

      final doc = await firestore
          .collection('reservas_canchas')
          .doc('cancelable')
          .get();
      expect(doc.exists, isFalse);

      // Si el slot no se hubiera liberado, esto fallaría con HorarioOcupadoException.
      await reservarCanchaAtomica(
        firestore: firestore,
        reserva: reserva(id: 'nueva_despues_de_cancelar', horaInicio: 14),
      );
    });
  });

  group('reservarCanchaAtomica – Pro-Shop (stock real)', () {
    test(
      'descuenta el stock atómicamente cuando hay suficiente',
      () async {
        await sembrarProductoProShop('paleta_1', stockActual: 3);

        await reservarCanchaAtomica(
          firestore: firestore,
          reserva: reserva(
            id: 'con_paleta',
            horaInicio: 10,
            itemsProShop: const [
              ItemProShopVenta(
                productoId: 'paleta_1',
                nombre: 'Paleta de prueba',
                cantidad: 2,
                precioUnitario: 1500,
              ),
            ],
          ),
        );

        final inv = await firestore
            .collection('inventario_general')
            .doc('paleta_1')
            .get();
        expect(inv.data()!['stockActual'], 1);

        final mov = await firestore.collection('movimientos_stock').get();
        expect(mov.docs.length, 1);
        expect(mov.docs.first.data()['cantidad'], -2);
        expect(mov.docs.first.data()['tipo'], 'Venta Pro-Shop Pádel');
      },
    );

    test(
      'rechaza la venta si no hay stock suficiente y no crea ni la reserva ni descuenta stock',
      () async {
        await sembrarProductoProShop('paleta_1', stockActual: 1);

        await expectLater(
          reservarCanchaAtomica(
            firestore: firestore,
            reserva: reserva(
              id: 'sin_stock',
              horaInicio: 10,
              itemsProShop: const [
                ItemProShopVenta(
                  productoId: 'paleta_1',
                  nombre: 'Paleta de prueba',
                  cantidad: 2,
                  precioUnitario: 1500,
                ),
              ],
            ),
          ),
          throwsA(isA<StockInsuficienteException>()),
        );

        final doc = await firestore
            .collection('reservas_canchas')
            .doc('sin_stock')
            .get();
        expect(doc.exists, isFalse);

        final inv = await firestore
            .collection('inventario_general')
            .doc('paleta_1')
            .get();
        expect(inv.data()!['stockActual'], 1);
      },
    );
  });

  group('cancelarReservaCanchaAtomica – Pro-Shop (stock real)', () {
    test('devuelve el stock vendido al cancelar la reserva', () async {
      await sembrarProductoProShop('paleta_1', stockActual: 3);

      final r = reserva(
        id: 'cancelable_con_paleta',
        horaInicio: 11,
        itemsProShop: const [
          ItemProShopVenta(
            productoId: 'paleta_1',
            nombre: 'Paleta de prueba',
            cantidad: 1,
            precioUnitario: 1500,
          ),
        ],
      );
      await reservarCanchaAtomica(firestore: firestore, reserva: r);

      final invAntes = await firestore
          .collection('inventario_general')
          .doc('paleta_1')
          .get();
      expect(invAntes.data()!['stockActual'], 2);

      await cancelarReservaCanchaAtomica(firestore: firestore, reserva: r);

      final invDespues = await firestore
          .collection('inventario_general')
          .doc('paleta_1')
          .get();
      expect(invDespues.data()!['stockActual'], 3);
    });
  });

  group('ReservaCanchaModel – migración de los campos de seña', () {
    test('toFirestore ya no escribe las claves viejas con ñ', () {
      final data = reserva(
        id: 'x',
        horaInicio: 10,
      ).toFirestore();

      expect(data.containsKey('seña_abonada'), isFalse);
      expect(data.containsKey('detalle_seña'), isFalse);
      expect(data['senaAbonada'], 0.0);
      expect(data['detalleSena'], '');
    });

    test(
      'fromFirestore sigue leyendo una reserva vieja guardada con las claves con ñ',
      () {
        final modelo = ReservaCanchaModel.fromFirestore('vieja', {
          'cancha': 'Cancha 1 Cristal',
          'nombreCliente': 'Socio viejo',
          'fecha': Timestamp.fromDate(DateTime(2026, 11, 16)),
          'horaInicio': 10,
          'duracionHoras': 1,
          'precio': 4500,
          'metodoPago': 'Efectivo',
          'seña_abonada': 1000.0,
          'detalle_seña': 'Señado con Efectivo',
        });

        expect(modelo.senaAbonada, 1000.0);
        expect(modelo.detalleSena, 'Señado con Efectivo');
      },
    );

    test(
      'fromFirestore prioriza las claves nuevas sobre las viejas si ambas están presentes',
      () {
        final modelo = ReservaCanchaModel.fromFirestore('mixta', {
          'cancha': 'Cancha 1 Cristal',
          'nombreCliente': 'Socio',
          'fecha': Timestamp.fromDate(DateTime(2026, 11, 16)),
          'horaInicio': 10,
          'duracionHoras': 1,
          'precio': 4500,
          'metodoPago': 'Efectivo',
          'senaAbonada': 2000.0,
          'detalleSena': 'Señado con MODO',
          'seña_abonada': 1000.0,
          'detalle_seña': 'Señado con Efectivo',
        });

        expect(modelo.senaAbonada, 2000.0);
        expect(modelo.detalleSena, 'Señado con MODO');
      },
    );
  });
}
