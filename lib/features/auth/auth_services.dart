import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<UserCredential?> iniciarSesionConGoogle() async {
    try {
      GoogleAuthProvider proveedorGoogle = GoogleAuthProvider();
      return await _auth.signInWithPopup(proveedorGoogle);
    } catch (e) {
      print("Error en el login de Firebase con Google: $e");
      return null;
    }
  }

  // 📝 REGISTRO CON EMAIL Y CREACIÓN AUTOMÁTICA EN FIRESTORE
  Future<UserCredential?> registrarConEmail(
    String email,
    String password,
  ) async {
    try {
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      // Crea el documento en la colección 'usuarios' inmediatamente
      if (cred.user != null) {
        final String emailLimpio = email.trim().toLowerCase();
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(cred.user!.uid)
            .set({
              'uid': cred.user!.uid,
              'email': emailLimpio,
              'rol': 'socio',
              'activo': true,
              'fechaCreacion': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

      return cred;
    } catch (e) {
      print("Error al registrar usuario: $e");
      return null;
    }
  }

  Future<UserCredential?> iniciarSesionConEmail(
    String email,
    String password,
  ) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
    } catch (e) {
      print("Error al iniciar sesión con email: $e");
      return null;
    }
  }

  Future<bool> recuperarContrasena(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } catch (e) {
      print("Error al enviar mail de recuperación: $e");
      return false;
    }
  }

  Future<void> cerrarSesion() async {
    try {
      await _auth.signOut();
    } catch (e) {
      print("Error al cerrar sesión: $e");
    }
  }

  // 🚀 OBTENER ROL OPTIMIZADO
  Future<String> obtenerRolUsuario(String uid) async {
    try {
      User? userActual = _auth.currentUser;
      if (userActual == null) {
        print("🚨 [AuthService] No hay usuario logueado en FirebaseAuth.");
        return 'socio';
      }

      final String emailActual = userActual.email?.trim().toLowerCase() ?? '';
      print(
        "🔍 [AuthService] Buscando rol para UID: '$uid' y Email: '$emailActual'",
      );

      // 1. BÚSQUEDA DIRECTA POR UID
      DocumentSnapshot docUid = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      if (docUid.exists && docUid.data() != null) {
        var docData = docUid.data() as Map<String, dynamic>;
        String rolEncontrado = docData['rol'] ?? 'socio';
        bool estaActivo = docData['activo'] ?? true;

        print(
          "🎯 [AuthService] Encontrado por UID ($uid) -> Rol: $rolEncontrado",
        );

        if (!estaActivo) return 'bloqueado';
        return rolEncontrado;
      }

      // 2. BÚSQUEDA SECUNDARIA POR EMAIL
      if (emailActual.isNotEmpty) {
        QuerySnapshot queryEmail = await FirebaseFirestore.instance
            .collection('usuarios')
            .where('email', isEqualTo: emailActual)
            .limit(1)
            .get();

        if (queryEmail.docs.isNotEmpty) {
          var docData = queryEmail.docs.first.data() as Map<String, dynamic>;
          String rolEncontrado = docData['rol'] ?? 'socio';
          bool estaActivo = docData['activo'] ?? true;

          print(
            "🎯 [AuthService] Encontrado por Email ($emailActual) -> Rol: $rolEncontrado",
          );

          if (!estaActivo) return 'bloqueado';
          return rolEncontrado;
        }
      }

      // 3. CREACIÓN SEGURA (Si no existe, crea el perfil)
      print(
        "⚠️ [AuthService] Usuario no hallado en Firestore. Creando registro básico...",
      );
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'uid': uid,
        'email': emailActual,
        'rol': 'socio',
        'activo': true,
        'fechaCreacion': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return 'socio';
    } catch (e) {
      print("🚨 [AuthService] Error al obtener rol: $e");
      return 'socio';
    }
  }
}
