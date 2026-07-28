import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_services.dart';
import '../dashboard/dashboard_page.dart';

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

  void _mostrarMensaje(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
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

    if (resultado != null && resultado.user != null && mounted) {
      String rol = await AuthService().obtenerRolUsuario(resultado.user!.uid);

      if (rol == 'bloqueado') {
        setState(() => _cargando = false);
        await AuthService().cerrarSesion();
        _mostrarMensaje(
          'Tu cuenta ha sido deshabilitada por la administración.',
          Colors.redAccent,
        );
        return;
      }

      setState(() => _cargando = false);
      _mostrarMensaje('¡Bienvenido/a al sistema!', const Color(0xFF0A3B43));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardPage(rolUsuario: rol),
          ),
        );
      }
    } else {
      setState(() => _cargando = false);
      _mostrarMensaje('Hubo un error. Verifica tus datos.', Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎨 Color Institucional Principal de OQUA
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
                // 🖼️ LOGO INSTITUCIONAL DE OQUA
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
                      ? 'Crea una cuenta administrativa para el club'
                      : 'Recupera el acceso a tu cuenta',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 30),

                // CAMPO EMAIL
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

                // CAMPO CONTRASEÑA
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

                // BOTÓN PRINCIPAL
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

                  // BOTÓN GOOGLE
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
                      final resultado = await AuthService()
                          .iniciarSesionConGoogle();
                      if (resultado != null &&
                          resultado.user != null &&
                          mounted) {
                        String rol = await AuthService().obtenerRolUsuario(
                          resultado.user!.uid,
                        );
                        _mostrarMensaje(
                          '¡Bienvenido/a, ${resultado.user?.displayName ?? 'Usuario'}!',
                          oquaPrimary,
                        );
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  DashboardPage(rolUsuario: rol),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],

                const SizedBox(height: 24),

                // CONMUTADOR
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
