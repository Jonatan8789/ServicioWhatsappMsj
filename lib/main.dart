import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; //
import 'features/auth/login_page.dart'; //

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized(); //[cite: 6]

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform, //[cite: 6]
    );
  } catch (e) {
    debugPrint('🚨 Error crítico inicializando Firebase: $e');
  }

  runApp(const MiClubApp()); //[cite: 6]
}

class MiClubApp extends StatelessWidget {
  const MiClubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, //[cite: 6]
      title: 'Aqua & Paddle Club', //[cite: 6]
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E293B), //[cite: 6]
        ),
        useMaterial3: true, //[cite: 6]
      ),
      // 📌 Nota: Si te logueás y no avanza, el problema está dentro de LoginPage o el AppShell que procesa los roles.
      home: const LoginPage(), //[cite: 6]
    );
  }
}
