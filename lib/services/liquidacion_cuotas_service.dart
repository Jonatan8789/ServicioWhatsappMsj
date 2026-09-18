import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:natatorio_app/features/socios/socio_model.dart';
import 'package:natatorio_app/features/tarifas/tarifa_model.dart';
import 'package:natatorio_app/services/familia_service.dart';

class LiquidacionCuotasService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FamiliaService _familiaService = FamiliaService();

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

      // 🚀 OPTIMIZACIÓN: antes esto hacía 2-3 lecturas de Firestore POR
      // SOCIO dentro del loop (verificación de cuota paga, verificación de
      // movimiento ya generado, conteo de grupo familiar) — con 500+ socios
      // activos eso son 1000-1500+ round-trips seriales antes de escribir
      // nada. Ahora se resuelve todo con 2 consultas `collectionGroup` (una
      // sola vez, fuera del loop) más un cálculo en memoria para el tamaño
      // de cada grupo familiar a partir de los socios activos ya cargados.
      final cuotasPagasSnap = await _firestore
          .collectionGroup('cuotas_pagas')
          .where('periodo', isEqualTo: periodo)
          .get();
      final Set<String> sociosConCuotaPaga = cuotasPagasSnap.docs
          .map((d) => d.reference.parent.parent!.id)
          .toSet();

      final movimientosPeriodoSnap = await _firestore
          .collectionGroup('cuenta_corriente')
          .where('periodo', isEqualTo: periodo)
          .get();
      final Set<String> sociosConMovimientoPeriodo = movimientosPeriodoSnap
          .docs
          .map((d) => d.reference.parent.parent!.id)
          .toSet();

      final Map<String, int> tamanoGrupoFamiliar = {};
      for (var doc in sociosSnap.docs) {
        final String? grupo = doc.data()['grupoFamiliarId']?.toString();
        if (grupo != null && grupo.isNotEmpty) {
          tamanoGrupoFamiliar[grupo] = (tamanoGrupoFamiliar[grupo] ?? 0) + 1;
        }
      }

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

        // 📌 3. VERIFICACIÓN ANTI-DUPLICACIÓN (resuelta arriba, sin I/O acá)
        if (sociosConCuotaPaga.contains(socio.id) ||
            sociosConMovimientoPeriodo.contains(socio.id)) {
          omitidosYaExistentes++;
          continue;
        }

        // 4. Cálculo de montos — descuento escolar vs. familiar NO se
        // acumulan (se aplica el mayor de los dos) para evitar descuentos
        // compuestos fuera de control.
        double descuentoPorcentaje = 0.0;
        String? motivoDescuento;
        if (socio.esEstudianteEscuela && socio.descuentoEscolarPorcentaje > 0) {
          descuentoPorcentaje = socio.descuentoEscolarPorcentaje;
          motivoDescuento = 'Escolar';
        }

        if (socio.grupoFamiliarId != null &&
            socio.grupoFamiliarId!.isNotEmpty) {
          final int integrantes =
              tamanoGrupoFamiliar[socio.grupoFamiliarId!] ?? 0;
          final double descuentoFamiliar = _familiaService.descuentoPorTamano(
            integrantes,
          );
          if (descuentoFamiliar > descuentoPorcentaje) {
            descuentoPorcentaje = descuentoFamiliar;
            motivoDescuento = 'Familiar';
          }
        }

        final double descuentoMonto = precioBase * (descuentoPorcentaje / 100);
        final double montoFinal = precioBase - descuentoMonto;

        final DocumentReference docMovimientoRef = _firestore
            .collection('socios')
            .doc(socio.id)
            .collection('cuenta_corriente')
            .doc();

        String detalleConcepto =
            'Cuota Mensual $nombreMes - ${socio.deporte} (${socio.frecuencia})';
        if (descuentoPorcentaje > 0) {
          detalleConcepto +=
              ' [Dto. $motivoDescuento ${descuentoPorcentaje.toStringAsFixed(0)}%]';
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
