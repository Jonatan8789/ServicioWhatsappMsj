import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_services.dart';
import '../dashboard/dashboard_page.dart';
import '../socios/socio_dashboard_page.dart'; // 👈 Import del Dashboard de Socios

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _modoActual = 'login';
  bool _cargando = false;

  void _mostrarMensaje(
    String mensaje,
    Color color, [
    BuildContext? currentContext,
  ]) {
    final ctx = currentContext ?? context;
    if (!mounted) return;
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
  }

  // 🪟 DIÁLOGO MODAL PARA VINCULAR DNI DEL SOCIO
  Future<bool> _solicitarVinculacionDni(String uid) async {
    final TextEditingController dniController = TextEditingController();
    bool vinculando = false;
    bool resultadoExitoso = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            const Color oquaPrimary = Color(0xFF0A3B43);

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.badge_outlined, color: oquaPrimary),
                  SizedBox(width: 10),
                  Text('Vinculación de Socio'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ingresa tu DNI para vincular tu cuenta con tu ficha en el padrón del club:',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: dniController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Número de DNI',
                      hintText: 'Ej: 38123456',
                      prefixIcon: const Icon(Icons.pin, color: oquaPrimary),
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
                  onPressed: vinculando
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                        },
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: oquaPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: vinculando
                      ? null
                      : () async {
                          final dni = dniController.text.trim();
                          if (dni.isEmpty) {
                            _mostrarMensaje(
                              'Ingresa un DNI válido.',
                              Colors.orange,
                              dialogContext,
                            );
                            return;
                          }

                          setDialogState(() => vinculando = true);
                          final resp = await AuthService().vincularSocioPorDni(
                            dni,
                          );

                          if (!dialogContext.mounted) return;

                          setDialogState(() => vinculando = false);

                          if (resp['exito'] == true) {
                            resultadoExitoso = true;
                            Navigator.pop(dialogContext);
                          } else {
                            _mostrarMensaje(
                              resp['mensaje'] ?? 'Error al vincular.',
                              Colors.redAccent,
                              dialogContext,
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
            );
          },
        );
      },
    );

    return resultadoExitoso;
  }

  // 🔄 FLUJO COMPLETO POST-AUTENTICACIÓN RECONOCIENDO EL ROL
  Future<void> _procesarPostLogin(User user, Color colorTema) async {
    String rol = await AuthService().obtenerRolUsuario(user.uid);

    if (rol == 'bloqueado') {
      setState(() => _cargando = false);
      await AuthService().cerrarSesion();
      _mostrarMensaje(
        'Tu cuenta ha sido deshabilitada por la administración.',
        Colors.redAccent,
      );
      return;
    }

    // 📱 SI ES SOCIO: VERIFICAR VINCULACIÓN Y REDIRIGIR A SU VISTA DEDICADA
    if (rol == 'socio') {
      bool yaVinculado = await AuthService().estaUsuarioVinculado(user.uid);

      if (!yaVinculado) {
        setState(() => _cargando = false);
        bool vinculadoOk = await _solicitarVinculacionDni(user.uid);

        if (!vinculadoOk) {
          await AuthService().cerrarSesion();
          _mostrarMensaje(
            'Debes estar registrado en el padrón de socios para ingresar.',
            Colors.orange,
          );
          return;
        }
      }

      // 🔍 Buscar el documento específico del socio en Firestore
      final snapSocio = await FirebaseFirestore.instance
          .collection('socios')
          .where('usuarioUid', isEqualTo: user.uid)
          .limit(1)
          .get();

      setState(() => _cargando = false);
      _mostrarMensaje('¡Bienvenido/a a tu portal de socio!', colorTema);

      if (mounted && snapSocio.docs.isNotEmpty) {
        final docSocio = snapSocio.docs.first;

        // 🎯 Redirección inteligente a la vista nativa de socio
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SocioDashboardPage(
              socioId: docSocio.id,
              socioData: docSocio.data(),
            ),
          ),
        );
        return;
      }
    }

    // 💻 SI ES ADMIN/STAFF: REDIRIGIR AL DASHBOARD COMPLETO WEB
    setState(() => _cargando = false);
    _mostrarMensaje('¡Bienvenido/a al sistema!', colorTema);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => DashboardPage(rolUsuario: rol)),
      );
    }
  }

  Future<void> _procesarFormulario() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty) {
      _mostrarMensaje(
        'Por favor, ingresa tu correo electrónico.',
        Colors.orange,
      );
      return;
    }

    setState(() => _cargando = true);

    if (_modoActual == 'recuperar') {
      final exito = await AuthService().recuperarContrasena(email);
      setState(() => _cargando = false);
      if (exito) {
        _mostrarMensaje(
          'Mail de recuperación enviado. Revisa tu casilla.',
          const Color(0xFF0A3B43),
        );
        setState(() => _modoActual = 'login');
      } else {
        _mostrarMensaje(
          'Error al enviar el mail. Verifica el correo.',
          Colors.redAccent,
        );
      }
      return;
    }

    if (password.isEmpty || password.length < 6) {
      _mostrarMensaje(
        'La contraseña debe tener al menos 6 caracteres.',
        Colors.orange,
      );
      setState(() => _cargando = false);
      return;
    }

    UserCredential? resultado;

    if (_modoActual == 'login') {
      resultado = await AuthService().iniciarSesionConEmail(email, password);
    } else if (_modoActual == 'registro') {
      resultado = await AuthService().registrarConEmail(email, password);
    }

    if (resultado != null && resultado.user != null) {
      await _procesarPostLogin(resultado.user!, const Color(0xFF0A3B43));
    } else {
      setState(() => _cargando = false);
      _mostrarMensaje('Hubo un error. Verifica tus datos.', Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color oquaPrimary = Color(0xFF0A3B43);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(40),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: oquaPrimary.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/logo_oqua.jpg',
                    height: 110,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: oquaPrimary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'OQUA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'OQUA CLUB',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _modoActual == 'login'
                      ? 'Gestión integral de socios y canchas'
                      : _modoActual == 'registro'
                      ? 'Crea una cuenta para operar en el club'
                      : 'Recupera el acceso a tu cuenta',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 30),

                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: oquaPrimary,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: oquaPrimary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (_modoActual != 'recuperar') ...[
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: oquaPrimary,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: oquaPrimary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                if (_modoActual == 'login')
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _modoActual = 'recuperar'),
                      child: const Text(
                        '¿Olvidaste tu contraseña?',
                        style: TextStyle(
                          color: oquaPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                _cargando
                    ? const CircularProgressIndicator(color: oquaPrimary)
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: oquaPrimary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _procesarFormulario,
                        child: Text(
                          _modoActual == 'login'
                              ? 'Iniciar Sesión'
                              : _modoActual == 'registro'
                              ? 'Registrarse'
                              : 'Enviar Correo de Recuperación',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),

                if (_modoActual == 'login') ...[
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'O',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                      Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                    ],
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      elevation: 0,
                    ),
                    icon: Image.network(
                      'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg',
                      height: 20,
                      width: 20,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.g_mobiledata_rounded,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    label: const Text(
                      'Entrar con Google',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () async {
                      setState(() => _cargando = true);
                      final resultado = await AuthService()
                          .iniciarSesionConGoogle();
                      if (resultado != null && resultado.user != null) {
                        await _procesarPostLogin(resultado.user!, oquaPrimary);
                      } else {
                        setState(() => _cargando = false);
                      }
                    },
                  ),
                ],

                const SizedBox(height: 24),

                TextButton(
                  onPressed: () {
                    setState(() {
                      _modoActual = _modoActual == 'login'
                          ? 'registro'
                          : 'login';
                    });
                  },
                  child: Text(
                    _modoActual == 'login'
                        ? '¿No tienes cuenta? Regístrate acá'
                        : '¿Ya tienes una cuenta? Inicia sesión',
                    style: const TextStyle(
                      color: oquaPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
