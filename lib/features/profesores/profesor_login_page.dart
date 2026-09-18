import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../auth/auth_services.dart';
import 'profesor_dashboard_page.dart';

/// Login móvil dedicado para profesores — antes este rol no tenía ninguna
/// pantalla de ingreso propia: 'profe' es un rol válido en usuarios_page.dart
/// pero dashboard_page.dart trataba a cualquier no-admin como socio, así que
/// un profesor quedaba en un callejón sin salida ("Ficha pendiente de
/// vinculación") sin importar el dispositivo. Usa Google Sign-In + el mismo
/// mecanismo de vinculación por DNI que ya usa login_page.dart para socios,
/// adaptado al padrón de 'profesores'.
class ProfesorLoginPage extends StatefulWidget {
  const ProfesorLoginPage({super.key});

  @override
  State<ProfesorLoginPage> createState() => _ProfesorLoginPageState();
}

class _ProfesorLoginPageState extends State<ProfesorLoginPage> {
  bool _cargando = false;
  static const Color primaryColor = Color(0xFF0A3B43);

  void _mostrarMensaje(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
  }

  Future<bool> _solicitarVinculacionDni() async {
    final TextEditingController dniController = TextEditingController();
    bool vinculando = false;
    bool resultadoExitoso = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.badge_outlined, color: primaryColor),
              SizedBox(width: 10),
              Text('Vinculación de Profesor'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresá tu DNI para vincular tu cuenta con tu ficha de profesor en el club:',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: dniController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Número de DNI',
                  hintText: 'Ej: 38123456',
                  prefixIcon: const Icon(Icons.pin, color: primaryColor),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: vinculando ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: vinculando
                  ? null
                  : () async {
                      final dni = dniController.text.trim();
                      if (dni.isEmpty) return;
                      setDialogState(() => vinculando = true);
                      final resp = await AuthService().vincularProfesorPorDni(
                        dni,
                      );
                      if (!dialogContext.mounted) return;
                      setDialogState(() => vinculando = false);
                      if (resp['exito'] == true) {
                        resultadoExitoso = true;
                        Navigator.pop(dialogContext);
                      } else {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(resp['mensaje'] ?? 'Error al vincular.'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
              child: vinculando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Vincular'),
            ),
          ],
        ),
      ),
    );

    return resultadoExitoso;
  }

  Future<void> _ingresarConGoogle() async {
    setState(() => _cargando = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _cargando = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCred = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        setState(() => _cargando = false);
        return;
      }

      final String rol = await AuthService().obtenerRolUsuario(user.uid);
      if (rol == 'bloqueado') {
        setState(() => _cargando = false);
        await AuthService().cerrarSesion();
        _mostrarMensaje(
          'Tu cuenta fue deshabilitada por la administración.',
          Colors.redAccent,
        );
        return;
      }
      if (rol != 'profe') {
        setState(() => _cargando = false);
        await AuthService().cerrarSesion();
        _mostrarMensaje(
          'Esta cuenta no está habilitada como profesor. Pedile a administración que te asigne el rol correspondiente.',
          Colors.orange,
        );
        return;
      }

      bool yaVinculado = await AuthService().estaProfesorVinculado(user.uid);
      if (!yaVinculado) {
        setState(() => _cargando = false);
        final vinculadoOk = await _solicitarVinculacionDni();
        if (!vinculadoOk) {
          await AuthService().cerrarSesion();
          _mostrarMensaje(
            'Debés estar registrado en el padrón de profesores para ingresar.',
            Colors.orange,
          );
          return;
        }
        setState(() => _cargando = true);
      }

      final snapProfesor = await FirebaseFirestore.instance
          .collection('profesores')
          .where('usuarioUid', isEqualTo: user.uid)
          .limit(1)
          .get();

      setState(() => _cargando = false);

      if (mounted && snapProfesor.docs.isNotEmpty) {
        final docProfesor = snapProfesor.docs.first;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ProfesorDashboardPage(
              profesorId: docProfesor.id,
              profesorData: docProfesor.data(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        _mostrarMensaje('Error al iniciar sesión: $e', Colors.redAccent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sports_rounded, size: 70, color: primaryColor),
                const SizedBox(height: 12),
                const Text(
                  'OQUA CLUB DEPORTIVO',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 1.1,
                  ),
                ),
                const Text(
                  'Portal Móvil para Profesores',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 36),
                _cargando
                    ? const CircularProgressIndicator(color: primaryColor)
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          side: BorderSide(color: Colors.grey.shade400),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(
                          Icons.g_mobiledata_rounded,
                          size: 30,
                          color: primaryColor,
                        ),
                        label: const Text(
                          'Ingresar con Gmail',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        onPressed: _ingresarConGoogle,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
