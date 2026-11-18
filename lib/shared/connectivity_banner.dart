import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Envuelve una pantalla y muestra una franja "Sin conexión" cuando el
/// dispositivo se queda sin internet — pensado para control de acceso y el
/// portal de profesores, que tienen que poder operar (con datos en caché)
/// en vestuarios/natatorio con mala señal, pero el staff necesita saber que
/// lo que ve puede estar desactualizado y que lo que carga recién se va a
/// sincronizar cuando vuelva la señal.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool _sinConexion = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _chequearInicial();
    _sub = Connectivity().onConnectivityChanged.listen((resultados) {
      final sinConexion = resultados.every((r) => r == ConnectivityResult.none);
      if (mounted) setState(() => _sinConexion = sinConexion);
    });
  }

  Future<void> _chequearInicial() async {
    final resultados = await Connectivity().checkConnectivity();
    final sinConexion = resultados.every((r) => r == ConnectivityResult.none);
    if (mounted) setState(() => _sinConexion = sinConexion);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_sinConexion)
          Container(
            width: double.infinity,
            color: Colors.orange.shade700,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Sin conexión — mostrando datos guardados. Se va a actualizar solo cuando vuelva la señal.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
