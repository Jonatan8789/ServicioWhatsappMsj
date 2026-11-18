import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'socio_dashboard_page.dart';
import '../profesores/profesor_login_page.dart';

class SocioLoginPage extends StatefulWidget {
  const SocioLoginPage({super.key});

  @override
  State<SocioLoginPage> createState() => _SocioLoginPageState();
}

class _SocioLoginPageState extends State<SocioLoginPage> {
  final _dniController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _cargando = false;

  static const Color primaryColor = Color(0xFF0A3B43);

  @override
  void dispose() {
    _dniController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 🔑 INGRESO CON DNI / CONTRASEÑA
  Future<void> _ingresarSocioDNI() async {
    final dni = _dniController.text.trim();
    final pass = _passwordController.text.trim();

    if (dni.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresá DNI y Contraseña')),
      );
      return;
    }

    setState(() => _cargando = true);

    try {
      final querySocio = await FirebaseFirestore.instance
          .collection('socios')
          .where('dni', isEqualTo: dni)
          .limit(1)
          .get();

      if (querySocio.docs.isEmpty) {
        setState(() => _cargando = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El DNI no figura en el padrón del club.'),
          ),
        );
        return;
      }

      final docSocio = querySocio.docs.first;
      final socioData = docSocio.data();
      final emailSocio = socioData['email'] ?? '$dni@oqua.club';

      final creds = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailSocio,
        password: pass,
      );

      if (creds.user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SocioDashboardPage(socioId: docSocio.id, socioData: socioData),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al ingresar: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // 🌐 INGRESO CON GOOGLE SIGN-IN
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
      final String userEmail = userCred.user?.email ?? '';

      // Buscar si existe el socio vinculado a este email
      final querySocio = await FirebaseFirestore.instance
          .collection('socios')
          .where('email', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (querySocio.docs.isEmpty) {
        setState(() => _cargando = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se encontró un socio registrado con el correo: $userEmail',
            ),
          ),
        );
        return;
      }

      final docSocio = querySocio.docs.first;
      final socioData = docSocio.data();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SocioDashboardPage(socioId: docSocio.id, socioData: socioData),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar sesión con Google: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
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
                const Icon(Icons.pool_rounded, size: 70, color: primaryColor),
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
                  'Portal Móvil para Socios',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _dniController,
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
                  controller: _passwordController,
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
                _cargando
                    ? const CircularProgressIndicator(color: primaryColor)
                    : Column(
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _ingresarSocioDNI,
                            child: const Text(
                              'Ingresar a mi Cuenta',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(child: Divider(color: Colors.grey.shade300)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'o ingresar con',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider(color: Colors.grey.shade300)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
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
                              'Gmail',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            onPressed: _ingresarConGoogle,
                          ),
                          const SizedBox(height: 20),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProfesorLoginPage(),
                              ),
                            ),
                            child: Text(
                              '¿Sos profesor? Ingresá acá',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
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