import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/auth/login_page.dart';
import 'features/auth/auth_services.dart';
import 'features/socios/socio_login_page.dart';
import 'features/socios/socio_dashboard_page.dart';
import 'features/profesores/profesor_dashboard_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme/app_theme.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('🚨 Error crítico inicializando Firebase: $e');
  }

  runApp(const MiClubApp());
}

class MiClubApp extends StatelessWidget {
  const MiClubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aqua & Paddle Club',
      theme: AppTheme.staff,

      // 📱/💻 DETECTOR INTELIGENTE DE PANTALLA
      home: LayoutBuilder(
        builder: (context, constraints) {
          // Si el ancho de pantalla es menor a 600px (Celular / PWA Móvil)
          if (constraints.maxWidth < 600) {
            return const FlujoMovilPorRol();
          }
          // Si es pantalla ancha (PC / Web Admin)
          return const LoginPage();
        },
      ),

      // Rutas para acceso directo
      routes: {
        '/admin': (context) => const LoginPage(),
        '/socio': (context) => const SocioLoginPage(),
      },
    );
  }
}

const Color _oquaPrimary = Color(0xFF0A3B43);

Widget _cargandoMovil() => const Scaffold(
  body: Center(child: CircularProgressIndicator(color: _oquaPrimary)),
);

// 📱 FLUJO AUTOMÁTICO MÓVIL — se fija el rol real (usuarios/{uid}.rol) antes
// de decidir a qué portal mandar. Antes esto asumía "todo el que entra por
// acá es socio" sin mirar el rol: un profesor que abriera la app en el
// celular terminaba en SocioLoginPage sin ninguna forma de ingresar.
class FlujoMovilPorRol extends StatelessWidget {
  const FlujoMovilPorRol({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _cargandoMovil();
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const SocioLoginPage();
        }

        final user = snapshot.data!;

        return FutureBuilder<String>(
          future: AuthService().obtenerRolUsuario(user.uid),
          builder: (context, rolSnap) {
            if (!rolSnap.hasData) return _cargandoMovil();

            final String rol = rolSnap.data!;

            if (rol == 'bloqueado') {
              return _BloqueadoMovilScaffold(uid: user.uid);
            }

            if (rol == 'profe') {
              return _FlujoMovilProfesor(uid: user.uid);
            }

            if (rol == 'admin') {
              return const _AdminSoloEscritorioScaffold();
            }

            // Default histórico: cualquier otro rol (incluido 'socio') pasa
            // por el flujo de socio, igual que antes de este cambio.
            return _FlujoMovilSocio(uid: user.uid);
          },
        );
      },
    );
  }
}

class _FlujoMovilSocio extends StatelessWidget {
  final String uid;
  const _FlujoMovilSocio({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('socios')
          .where('usuarioUid', isEqualTo: uid)
          .limit(1)
          .snapshots(),
      builder: (context, socioSnap) {
        if (socioSnap.connectionState == ConnectionState.waiting) {
          return _cargandoMovil();
        }

        if (socioSnap.hasData && socioSnap.data!.docs.isNotEmpty) {
          final doc = socioSnap.data!.docs.first;
          return SocioDashboardPage(
            socioId: doc.id,
            socioData: doc.data() as Map<String, dynamic>,
          );
        }

        return const SocioLoginPage();
      },
    );
  }
}

class _FlujoMovilProfesor extends StatefulWidget {
  final String uid;
  const _FlujoMovilProfesor({required this.uid});

  @override
  State<_FlujoMovilProfesor> createState() => _FlujoMovilProfesorState();
}

class _FlujoMovilProfesorState extends State<_FlujoMovilProfesor> {
  final TextEditingController _dniController = TextEditingController();
  bool _vinculando = false;
  String? _error;

  @override
  void dispose() {
    _dniController.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    final dni = _dniController.text.trim();
    if (dni.isEmpty) return;
    setState(() {
      _vinculando = true;
      _error = null;
    });
    final resp = await AuthService().vincularProfesorPorDni(dni);
    if (!mounted) return;
    setState(() => _vinculando = false);
    if (resp['exito'] != true) {
      setState(() => _error = resp['mensaje'] ?? 'Error al vincular.');
    }
    // Si salió bien, el StreamBuilder de abajo detecta el nuevo
    // 'usuarioUid' en el padrón y navega solo al dashboard de profesor.
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('profesores')
          .where('usuarioUid', isEqualTo: widget.uid)
          .limit(1)
          .snapshots(),
      builder: (context, profeSnap) {
        if (profeSnap.connectionState == ConnectionState.waiting) {
          return _cargandoMovil();
        }

        if (profeSnap.hasData && profeSnap.data!.docs.isNotEmpty) {
          final doc = profeSnap.data!.docs.first;
          return ProfesorDashboardPage(
            profesorId: doc.id,
            profesorData: doc.data() as Map<String, dynamic>,
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 60,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Vinculación de Profesor',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ingresá tu DNI para vincular tu cuenta con tu ficha en el padrón de profesores.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _dniController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Número de DNI',
                        prefixIcon: const Icon(
                          Icons.pin,
                          color: _oquaPrimary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _oquaPrimary,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _vinculando ? null : _vincular,
                        child: _vinculando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Vincular',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => AuthService().cerrarSesion(),
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BloqueadoMovilScaffold extends StatelessWidget {
  final String uid;
  const _BloqueadoMovilScaffold({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block_rounded, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Tu cuenta fue deshabilitada por la administración.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => AuthService().cerrarSesion(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSoloEscritorioScaffold extends StatelessWidget {
  const _AdminSoloEscritorioScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.desktop_windows_rounded,
                size: 60,
                color: _oquaPrimary,
              ),
              const SizedBox(height: 16),
              const Text(
                'El panel de administración todavía no está optimizado para celular.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Entrá desde una computadora o tablet para usarlo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => AuthService().cerrarSesion(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
