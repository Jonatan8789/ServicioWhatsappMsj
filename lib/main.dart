import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/auth/login_page.dart';
import 'features/socios/socio_login_page.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E293B)),
        useMaterial3: true,
      ),

      // 💻 Mantiene la Web Administrativa como punto inicial por defecto
      home: const LoginPage(),

      // 📱 Rutas para acceder a las aplicaciones móviles aisladas
      routes: {
        '/admin': (context) => const LoginPage(),
        '/socio': (context) => const SocioLoginPage(),
      },
    );
  }
}
