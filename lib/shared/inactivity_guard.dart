import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Envuelve una pantalla autenticada (el shell de admin, por ejemplo) y
/// cierra la sesión sola después de [timeout] sin actividad del mouse,
/// teclado o touch. Antes el sistema no tenía ningún timeout — la sesión
/// quedaba abierta indefinidamente en una terminal compartida (caja, kiosco)
/// hasta que alguien cerrara sesión a mano.
///
/// Cualquier evento de puntero o tecla en cualquier parte del árbol hijo
/// reinicia el contador (vía [Listener]/[KeyboardListener] en modo
/// translúcido, así no interfiere con los gestos de los widgets hijos).
class InactivityGuard extends StatefulWidget {
  final Widget child;
  final Duration timeout;

  const InactivityGuard({
    super.key,
    required this.child,
    this.timeout = const Duration(minutes: 30),
  });

  @override
  State<InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends State<InactivityGuard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reiniciarTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reiniciarTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _cerrarPorInactividad);
  }

  Future<void> _cerrarPorInactividad() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    await FirebaseAuth.instance.signOut();
    // El StreamBuilder de authStateChanges() en main.dart detecta el
    // signOut y vuelve solo a la pantalla de login — no hace falta navegar
    // manualmente acá.
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reiniciarTimer(),
      onPointerMove: (_) => _reiniciarTimer(),
      onPointerSignal: (_) => _reiniciarTimer(),
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
        onKeyEvent: (_) => _reiniciarTimer(),
        child: widget.child,
      ),
    );
  }
}
