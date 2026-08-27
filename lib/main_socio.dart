import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'features/socios/socio_login_page.dart';
import 'features/socios/socio_dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Error inicializando Firebase en APK Socio: $e');
  }

  runApp(const SocioApp());
}

class SocioApp extends StatelessWidget {
  const SocioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Oqua Socios',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A3B43)),
        useMaterial3: true,
      ),
      // 📱 Verificador estricto de sesión en segundo plano
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF0A3B43)),
              ),
            );
          }

          // Si NO hay sesión abierta, va al Login Móvil de Socios
          if (!snapshot.hasData || snapshot.data == null) {
            return const SocioLoginPage();
          }

          final user = snapshot.data!;

          // Si SÍ hay sesión abierta, busca únicamente su ficha en la colección 'socios'
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

              // Si la cuenta no está vinculada aún, va al login para que vincule su DNI
              return const SocioLoginPage();
            },
          );
        },
      ),
    );
  }
}
