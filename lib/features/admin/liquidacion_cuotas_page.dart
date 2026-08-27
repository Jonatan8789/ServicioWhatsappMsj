import 'package:flutter/material.dart';
import '../../services/liquidacion_cuotas_service.dart';

class LiquidacionCuotasPage extends StatefulWidget {
  const LiquidacionCuotasPage({super.key});

  @override
  State<LiquidacionCuotasPage> createState() => _LiquidacionCuotasPageState();
}

class _LiquidacionCuotasPageState extends State<LiquidacionCuotasPage> {
  bool _procesando = false;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  final Map<int, String> _meses = {
    1: 'Enero',
    2: 'Febrero',
    3: 'Marzo',
    4: 'Abril',
    5: 'Mayo',
    6: 'Junio',
    7: 'Julio',
    8: 'Agosto',
    9: 'Septiembre',
    10: 'Octubre',
    11: 'Noviembre',
    12: 'Diciembre',
  };

  Map<String, dynamic>? _ultimoResultado;

  Future<void> _ejecutarLiquidacion() async {
    final String mesNombre = _meses[_mesSeleccionado]!;
    final String periodoStr =
        "$_anioSeleccionado-${_mesSeleccionado.toString().padLeft(2, '0')}";

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Facturación Masiva'),
        content: Text(
          '¿Deseás generar las cuotas mensuales de $mesNombre $_anioSeleccionado para todos los socios activos?\n\n'
          'Se debitará en la cuenta corriente de cada socio según su tarifa asignada. Los socios con promociones vigentes de 3/6 meses serán omitidos automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sí, Liquidar Cuotas',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _procesando = true);

    final resultado = await LiquidacionCuotasService().generarCuotasPeriodo(
      periodo: periodoStr,
      nombreMes: "$mesNombre $_anioSeleccionado",
    );

    setState(() {
      _procesando = false;
      _ultimoResultado = resultado;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Liquidación Masiva de Cuotas',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const Text(
            'Generá el débito mensual de cuotas sociales para todos los socios activos.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. Selección del Período a Facturar',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _mesSeleccionado,
                        decoration: const InputDecoration(
                          labelText: 'Mes',
                          border: OutlineInputBorder(),
                        ),
                        items: _meses.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _mesSeleccionado = v!),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _anioSeleccionado,
                        decoration: const InputDecoration(
                          labelText: 'Año',
                          border: OutlineInputBorder(),
                        ),
                        items: [2025, 2026, 2027]
                            .map(
                              (a) => DropdownMenuItem(
                                value: a,
                                child: Text(a.toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _anioSeleccionado = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                    ),
                    onPressed: _procesando ? null : _ejecutarLiquidacion,
                    icon: _procesando
                        ? const SizedBox.shrink()
                        : const Icon(
                            Icons.request_quote_rounded,
                            color: Colors.white,
                          ),
                    label: _procesando
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'EJECUTAR LIQUIDACIÓN MASIVA',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          if (_ultimoResultado != null) ...[
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _ultimoResultado!['exito'] == true
                    ? const Color(0xFFF0FDF4)
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _ultimoResultado!['exito'] == true
                      ? Colors.green.shade300
                      : Colors.red.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ultimoResultado!['exito'] == true
                        ? '✅ Liquidación Procesada Exitosamente'
                        : '❌ Error en Proceso de Liquidación',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _ultimoResultado!['exito'] == true
                          ? Colors.green.shade900
                          : Colors.red.shade900,
                    ),
                  ),
                  const Divider(height: 24),
                  if (_ultimoResultado!['exito'] == true) ...[
                    Text(
                      '• Cuotas Generadas: ${_ultimoResultado!['procesados']} socios.',
                    ),
                    Text(
                      '• Socios Cubiertos por Promoción Vigente: ${_ultimoResultado!['omitidosPorPromocion'] ?? 0}.',
                    ),
                    Text(
                      '• Socios Omitidos (Ya poseían cuota del mes): ${_ultimoResultado!['omitidos']}.',
                    ),
                    Text(
                      '• Omitidos por Falta de Tarifa: ${_ultimoResultado!['fallidosSinTarifa']}.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Monto Total Facturado: \$${(_ultimoResultado!['totalDebitado'] as double).toStringAsFixed(2)} ARS',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ] else
                    Text('Detalle del error: ${_ultimoResultado!['error']}'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
