import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natatorio_app/features/socios/socio_model.dart';
import 'package:natatorio_app/features/tarifas/tarifa_model.dart';

class LiquidacionCuotasService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Ejecuta la generación masiva de cuotas para un período dado (ej: "2026-08")
  Future<Map<String, dynamic>> generarCuotasPeriodo({
    required String periodo, // Formato "YYYY-MM"
    required String nombreMes, // Ej: "Agosto 2026"
  }) async {
    int procesados = 0;
    int omitidosYaExistentes = 0;
    int fallidosSinTarifa = 0;
    double totalDebitado = 0.0;

    try {
      // 1. Obtener matriz de tarifas
      final tarifasSnap = await _firestore.collection('tarifas').get();
      final Map<String, double> mapaTarifas = {};
      for (var doc in tarifasSnap.docs) {
        final tarifa = TarifaModel.fromFirestore(doc.id, doc.data());
        final clave = "${tarifa.deporte}_${tarifa.frecuencia}";
        mapaTarifas[clave] = tarifa.precio;
      }

      // 2. Obtener todos los socios activos
      final sociosSnap = await _firestore
          .collection('socios')
          .where('activo', isEqualTo: true)
          .get();

      WriteBatch batch = _firestore.batch();
      int contadorBatch = 0;

      for (var docSocio in sociosSnap.docs) {
        final socio = SocioModel.fromFirestore(docSocio);

        // Clave para cruzar con tarifario
        final claveTarifa = "${socio.deporte}_${socio.frecuencia}";
        final double? precioBase = mapaTarifas[claveTarifa];

        if (precioBase == null || precioBase <= 0) {
          fallidosSinTarifa++;
          continue;
        }

        // 📌 3. VERIFICACIÓN ANTI-DUPLICACIÓN (Incluye Cobros Adelantados / Manuales)
        // Buscamos si ya existe cualquier movimiento generado para este período específico
        final cuotaExistenteSnap = await _firestore
            .collection('socios')
            .doc(socio.id)
            .collection('cuenta_corriente')
            .where('periodo', isEqualTo: periodo)
            .limit(1)
            .get();

        if (cuotaExistenteSnap.docs.isNotEmpty) {
          // Si el socio ya pagó por adelantado o ya se le liquidó, se omite
          omitidosYaExistentes++;
          continue;
        }

        // 4. Cálculo de montos y descuentos
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

        // 5. Registrar el débito en la cuenta corriente
        batch.set(docMovimientoRef, {
          'fecha': DateTime.now(),
          'tipo': 'Cuota Mensual',
          'periodo': periodo,
          'concepto': detalleConcepto,
          'precioBase': precioBase,
          'descuentoAplicado': descuentoMonto,
          'monto': montoFinal,
          'estado':
              'Pendiente', // Nace pendiente para el cobro masivo/individual
          'origen': 'LIQUIDACION_MASIVA',
          'facturadoArca': false, // Flag listo para la integración fiscal
        });

        // Actualizar saldo general de cuenta corriente del socio (negativo representa deuda)
        final DocumentReference socioRef = _firestore
            .collection('socios')
            .doc(socio.id);
        batch.update(socioRef, {
          'saldoCuentaCorriente': FieldValue.increment(-montoFinal),
        });

        procesados++;
        totalDebitado += montoFinal;
        contadorBatch += 2;

        // Limite de Batch en Firestore (500 operaciones max)
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
        'fallidosSinTarifa': fallidosSinTarifa,
        'totalDebitado': totalDebitado,
      };
    } catch (e) {
      return {'exito': false, 'error': e.toString()};
    }
  }
}
