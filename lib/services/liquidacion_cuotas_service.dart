import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natatorio_app/features/socios/socio_model.dart';
import 'package:natatorio_app/features/tarifas/tarifa_model.dart';

class LiquidacionCuotasService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> generarCuotasPeriodo({
    required String periodo, // "YYYY-MM"
    required String nombreMes, // "Agosto 2026"
  }) async {
    int procesados = 0;
    int omitidosYaExistentes = 0;
    int omitidosPorPromocion = 0; // 👈 NUEVO: Contador de promos vigentes
    int fallidosSinTarifa = 0;
    double totalDebitado = 0.0;

    try {
      final tarifasSnap = await _firestore.collection('tarifas').get();
      final List<TarifaModel> listaTarifas = [];
      for (var doc in tarifasSnap.docs) {
        listaTarifas.add(TarifaModel.fromFirestore(doc.id, doc.data()));
      }

      final DateTime hoy = DateTime.now();

      final sociosSnap = await _firestore
          .collection('socios')
          .where('activo', isEqualTo: true)
          .get();

      WriteBatch batch = _firestore.batch();
      int contadorBatch = 0;

      for (var docSocio in sociosSnap.docs) {
        final socio = SocioModel.fromFirestore(docSocio);

        // 🌟 1. VERIFICACIÓN DE EXENCIÓN POR PROMOCIÓN MULTIMES VIGENTE
        if (socio.mesesCubiertosHasta != null &&
            socio.mesesCubiertosHasta!.compareTo(periodo) >= 0) {
          omitidosPorPromocion++;
          continue; // No le genera cuota este mes porque tiene la promo paga
        }

        // 🔍 2. Buscar la tarifa mensual regular
        double? precioBase;
        for (var tarifa in listaTarifas) {
          if (tarifa.deporte == socio.deporte &&
              tarifa.frecuencia == socio.frecuencia &&
              tarifa.esVigenteEn(hoy)) {
            precioBase = tarifa.precioRegular;
            break;
          }
        }

        if (precioBase == null || precioBase <= 0) {
          fallidosSinTarifa++;
          continue;
        }

        // 📌 3. VERIFICACIÓN ANTI-DUPLICACIÓN
        final cuotaPagaSnap = await _firestore
            .collection('socios')
            .doc(socio.id)
            .collection('cuotas_pagas')
            .doc(periodo)
            .get();

        if (cuotaPagaSnap.exists) {
          omitidosYaExistentes++;
          continue;
        }

        final cuotaExistenteSnap = await _firestore
            .collection('socios')
            .doc(socio.id)
            .collection('cuenta_corriente')
            .where('periodo', isEqualTo: periodo)
            .limit(1)
            .get();

        if (cuotaExistenteSnap.docs.isNotEmpty) {
          omitidosYaExistentes++;
          continue;
        }

        // 4. Cálculo de montos
        double descuentoMonto = 0.0;
        if (socio.esEstudianteEscuela && socio.descuentoEscolarPorcentaje > 0) {
          descuentoMonto =
              precioBase * (socio.descuentoEscolarPorcentaje / 100);
        }
        final double montoFinal = precioBase - descuentoMonto;

        final DocumentReference docMovimientoRef = _firestore
            .collection('socios')
            .doc(socio.id)
            .collection('cuenta_corriente')
            .doc();

        String detalleConcepto =
            'Cuota Mensual $nombreMes - ${socio.deporte} (${socio.frecuencia})';
        if (socio.esEstudianteEscuela && socio.descuentoEscolarPorcentaje > 0) {
          detalleConcepto +=
              ' [Dto. Escolar ${socio.descuentoEscolarPorcentaje.toStringAsFixed(0)}%]';
        }

        batch.set(docMovimientoRef, {
          'fecha': DateTime.now(),
          'tipo': 'Cuota Mensual',
          'periodo': periodo,
          'mesPeriodo': periodo,
          'concepto': detalleConcepto,
          'precioBase': precioBase,
          'descuentoAplicado': descuentoMonto,
          'monto': montoFinal,
          'estado': 'Pendiente',
          'origen': 'LIQUIDACION_MASIVA',
          'facturadoArca': false,
        });

        final DocumentReference socioRef = _firestore
            .collection('socios')
            .doc(socio.id);
        batch.update(socioRef, {
          'saldoCuentaCorriente': FieldValue.increment(-montoFinal),
        });

        procesados++;
        totalDebitado += montoFinal;
        contadorBatch += 2;

        if (contadorBatch >= 450) {
          await batch.commit();
          batch = _firestore.batch();
          contadorBatch = 0;
        }
      }

      if (contadorBatch > 0) {
        await batch.commit();
      }

      return {
        'exito': true,
        'procesados': procesados,
        'omitidos': omitidosYaExistentes,
        'omitidosPorPromocion': omitidosPorPromocion,
        'fallidosSinTarifa': fallidosSinTarifa,
        'totalDebitado': totalDebitado,
      };
    } catch (e) {
      return {'exito': false, 'error': e.toString()};
    }
  }
}
