import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'socio_dashboard_page.dart';

class SocioLoginPage extends StatefulWidget {
  const SocioLoginPage({super.key});

  @override
  State<SocioLoginPage> createState() => _SocioLoginPageState();
}

class _SocioLoginPageState extends State<SocioLoginPage> {
  final _dniController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _cargando = false;

  Future<void> _ingresarSocio() async {
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
        // 📱 Navegación exclusiva al Dashboard de Socio
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0A3B43);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
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
                ),
              ),
              const Text(
                'Portal Móvil para Socios',
                style: TextStyle(color: Colors.grey),
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
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _ingresarSocio,
                      child: const Text(
                        'Ingresar a mi Cuenta',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
