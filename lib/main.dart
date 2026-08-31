import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/auth/login_page.dart';
import 'features/socios/socio_login_page.dart';
import 'features/socios/socio_dashboard_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

      // 📱/💻 DETECTOR INTELIGENTE DE PANTALLA
      home: LayoutBuilder(
        builder: (context, constraints) {
          // Si el ancho de pantalla es menor a 600px (Celular / PWA Móvil)
          if (constraints.maxWidth < 600) {
            return const SocioFlujoMovil();
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

// 📱 FLUJO AUTOMÁTICO MÓVIL PARA SOCIOS
class SocioFlujoMovil extends StatelessWidget {
  const SocioFlujoMovil({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF0A3B43)),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const SocioLoginPage();
        }

        final user = snapshot.data!;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('socios')
              .where('usuarioUid', isEqualTo: user.uid)
              .limit(1)
              .snapshots(),
          builder: (context, socioSnap) {
            if (socioSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0A3B43)),
                ),
              );
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
      },
    );
  }
}
