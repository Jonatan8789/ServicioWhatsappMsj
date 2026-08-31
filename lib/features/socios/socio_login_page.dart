import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';

class SocioLoginPage extends StatefulWidget {
  const SocioLoginPage({super.key});

  @override
  State<SocioLoginPage> createState() => _SocioLoginPageState();
}

class _SocioLoginPageState extends State<SocioLoginPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();

  final _dniCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _cargando = false;
  bool _soportaBiometria = false;

  @override
  void initState() {
    super.initState();
    _verificarSoporteBiometrico();
  }

  @override
  void dispose() {
    _dniCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // 🔒 VERIFICAR SI EL DISPOSITIVO SOPORTA HUELLES / FACE ID
  Future<void> _verificarSoporteBiometrico() async {
    try {
      final bool canAuthenticateWithBiometrics =
          await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();

      setState(() {
        _soportaBiometria = canAuthenticateWithBiometrics && isDeviceSupported;
      });
    } catch (e) {
      debugPrint("Error verificando biometría: $e");
    }
  }

  // 🔑 AUTENTICACIÓN BIOMÉTRICA (HUELLA / FACE ID)
  Future<void> _autenticarConBiometria() async {
    try {
      final bool autenticado = await _localAuth.authenticate(
        localizedReason: 'Escaneá tu huella o rostro para ingresar a Oqua Club',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (autenticado) {
        // Verificar si existe una sesión previa/guardada de usuario
        final userActual = _auth.currentUser;
        if (userActual != null) {
          _verificarYRedirigirSocio(userActual.uid);
        } else {
          _snack(
            'Iniciá sesión con DNI o Gmail la primera vez para activar la biometría.',
            Colors.orange,
          );
        }
      }
    } catch (e) {
      _snack('Error en la autenticación biométrica: $e', Colors.red);
    }
  }

  // 🌐 LOGIN CON GMAIL / GOOGLE SIGN-IN
  Future<void> _iniciarSesionConGoogle() async {
    setState(() => _cargando = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _cargando = false);
        return; // El usuario canceló la selección
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        await _vincularONavegarGoogleUser(user);
      }
    } catch (e) {
      _snack('Error al iniciar sesión con Google: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _vincularONavegarGoogleUser(User user) async {
    // Buscar si ya existe una ficha con su email o UID
    final querySocio = await _firestore
        .collection('socios')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .get();

    if (querySocio.docs.isNotEmpty) {
      // Si existe la ficha, asociamos el UID si no lo tenía asignado
      final docRef = querySocio.docs.first.reference;
      await docRef.update({'usuarioUid': user.uid});
      _snack(
        '¡Bienvenido! Sesión vinculada con tu cuenta de Gmail.',
        Colors.green,
      );
    } else {
      _snack(
        'Cuenta de Gmail autenticada. Verificá que tu correo esté registrado en la administración del club.',
        Colors.amber,
      );
    }
  }

  // 📄 LOGIN TRADICIONAL CON DNI Y CONTRASEÑA
  Future<void> _iniciarSesionDni() async {
    final dni = _dniCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (dni.isEmpty || pass.isEmpty) {
      _snack('Ingresá tu DNI y contraseña.', Colors.orange);
      return;
    }

    setState(() => _cargando = true);
    try {
      // Buscar el socio por DNI
      final query = await _firestore
          .collection('socios')
          .where('dni', isEqualTo: dni)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _snack(
          'No se encontró un socio registrado con el DNI $dni.',
          Colors.red,
        );
        return;
      }

      final dataSocio = query.docs.first.data();
      final emailSocio = dataSocio['email'] ?? '$dni@oquaclub.com';

      // Autenticar en Firebase Auth
      final userCred = await _auth.signInWithEmailAndPassword(
        email: emailSocio,
        password: pass,
      );

      if (userCred.user != null) {
        await query.docs.first.reference.update({
          'usuarioUid': userCred.user!.uid,
        });
      }
    } catch (e) {
      _snack('Credenciales incorrectas. Verificá tu contraseña.', Colors.red);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _verificarYRedirigirSocio(String uid) async {
    final query = await _firestore
        .collection('socios')
        .where('usuarioUid', isEqualTo: uid)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      _snack('¡Acceso Biométrico Exitoso!', Colors.green);
    } else {
      _snack(
        'No se encontró ficha de socio vinculada a este dispositivo.',
        Colors.orange,
      );
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0A3B43);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO / ICONO
                const Icon(Icons.pool_rounded, size: 72, color: primaryColor),
                const SizedBox(height: 16),
                const Text(
                  'OQUA CLUB DEPORTIVO',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                    letterSpacing: 1.1,
                  ),
                ),
                const Text(
                  'Portal Móvil para Socios',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 36),

                // CAMPOS DE DNI Y CONTRASEÑA
                TextField(
                  controller: _dniCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Número de DNI',
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      color: primaryColor,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: primaryColor,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // BOTÓN INGRESAR CON DNI
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _cargando ? null : _iniciarSesionDni,
                    child: _cargando
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Ingresar a mi Cuenta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // SEPARADOR DE OPCIONES
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Text(
                        'o ingresar con',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),

                // BOTONES ALTERNATIVOS: GMAIL Y BIOMETRÍA
                Row(
                  children: [
                    // 🌐 Botón Google / Gmail
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _cargando ? null : _iniciarSesionConGoogle,
                        icon: Image.network(
                          'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg',
                          height: 20,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.g_mobiledata, size: 24),
                        ),
                        label: const Text(
                          'Gmail',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // 👆 Botón Biométrico (Huella / Face ID)
                    if (_soportaBiometria) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: _autenticarConBiometria,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: primaryColor),
                            borderRadius: BorderRadius.circular(12),
                            color: const Color(0xFFEFF6FF),
                          ),
                          child: const Icon(
                            Icons.fingerprint,
                            color: primaryColor,
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
