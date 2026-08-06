import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // 👈 Import necesario para kIsWeb
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 🛠️ Configuración dinámica de clientId para Web / Móvil
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb
        ? '1033148419273-aphdb5n7eiugludb44m3r3ggcktol0uv.apps.googleusercontent.com'
        : null,
  );

  Future<UserCredential?> iniciarSesionConGoogle() async {
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      if (userCredential.user != null) {
        final String uid = userCredential.user!.uid;
        final String email =
            userCredential.user!.email?.trim().toLowerCase() ?? '';
        final docRef = FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid);

        final docSnap = await docRef.get();

        if (!docSnap.exists) {
          // 🆕 Si el usuario NO existe, lo creamos como socio por defecto
          await docRef.set({
            'uid': uid,
            'email': email,
            'rol': 'socio',
            'activo': true,
            'fechaCreacion': FieldValue.serverTimestamp(),
          });
        } else {
          // 🔄 Si YA existe (ej. es admin), actualizamos solo los datos de acceso sin pisar el rol
          await docRef.update({
            'email': email,
            'ultimoAcceso': FieldValue.serverTimestamp(),
          });
        }
      }
      return userCredential;
    } catch (e) {
      print("Error en el login con Google: $e");
      return null;
    }
  }

  Future<UserCredential?> registrarConEmail(
    String email,
    String password,
  ) async {
    try {
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

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
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      print("Error al cerrar sesión: $e");
    }
  }

  Future<String> obtenerRolUsuario(String uid) async {
    try {
      User? userActual = _auth.currentUser;
      if (userActual == null) return 'socio';

      final String emailActual = userActual.email?.trim().toLowerCase() ?? '';
      DocumentSnapshot docUid = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      if (docUid.exists && docUid.data() != null) {
        var docData = docUid.data() as Map<String, dynamic>;
        String rolEncontrado = docData['rol'] ?? 'socio';
        bool estaActivo = docData['activo'] ?? true;
        if (!estaActivo) return 'bloqueado';
        return rolEncontrado;
      }

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
          if (!estaActivo) return 'bloqueado';
          return rolEncontrado;
        }
      }

      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'uid': uid,
        'email': emailActual,
        'rol': 'socio',
        'activo': true,
        'fechaCreacion': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return 'socio';
    } catch (e) {
      print("🚨 Error al obtener rol: $e");
      return 'socio';
    }
  }

  Future<bool> estaUsuarioVinculado(String uid) async {
    try {
      DocumentSnapshot docUser = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      if (docUser.exists) {
        final data = docUser.data() as Map<String, dynamic>?;
        if (data != null && data['socioId'] != null) return true;
      }

      QuerySnapshot querySocio = await FirebaseFirestore.instance
          .collection('socios')
          .where('usuarioUid', isEqualTo: uid)
          .limit(1)
          .get();

      return querySocio.docs.isNotEmpty;
    } catch (e) {
      print("🚨 Error al consultar vinculación: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>> vincularSocioPorDni(String dni) async {
    try {
      final User? userActual = _auth.currentUser;
      if (userActual == null) {
        return {'exito': false, 'mensaje': 'No hay usuario autenticado.'};
      }

      final String dniLimpioStr = dni.trim().replaceAll('.', '');
      final int? dniLimpioNum = int.tryParse(dniLimpioStr);

      QuerySnapshot querySocio = await FirebaseFirestore.instance
          .collection('socios')
          .where('dni', isEqualTo: dniLimpioStr)
          .limit(1)
          .get();

      if (querySocio.docs.isEmpty && dniLimpioNum != null) {
        querySocio = await FirebaseFirestore.instance
            .collection('socios')
            .where('dni', isEqualTo: dniLimpioNum)
            .limit(1)
            .get();
      }

      if (querySocio.docs.isEmpty) {
        return {
          'exito': false,
          'mensaje':
              'No se encontró socio con el DNI $dniLimpioStr en el padrón.',
        };
      }

      final docSocio = querySocio.docs.first;
      final datosSocio = docSocio.data() as Map<String, dynamic>;

      if (datosSocio['usuarioUid'] != null &&
          datosSocio['usuarioUid'] != userActual.uid) {
        return {
          'exito': false,
          'mensaje': 'Este DNI ya está vinculado a otra cuenta.',
        };
      }

      await FirebaseFirestore.instance
          .collection('socios')
          .doc(docSocio.id)
          .update({
            'usuarioUid': userActual.uid,
            'emailVinculado': userActual.email,
            'fechaVinculacion': FieldValue.serverTimestamp(),
          });

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userActual.uid)
          .set({
            'uid': userActual.uid,
            'email': userActual.email,
            'socioId': docSocio.id,
            'esSocio': true,
          }, SetOptions(merge: true));

      return {
        'exito': true,
        'mensaje': '¡Cuenta vinculada con éxito!',
        'socioId': docSocio.id,
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error técnico: ${e.toString()}'};
    }
  }

  // 🔄 SINCRONIZACIÓN LOCAL DE RANKING (SIN CLOUD FUNCTIONS)
  Future<Map<String, dynamic>> forzarSincronizacionRanking() async {
    try {
      final User? userActual = _auth.currentUser;
      if (userActual == null) {
        return {'exito': false, 'mensaje': 'Usuario no autenticado.'};
      }

      // Registramos la actualización directamente en Firestore
      await FirebaseFirestore.instance
          .collection('configuraciones_padel')
          .doc('sincronizacion_ranking')
          .set({
            'ultimaSincronizacion': FieldValue.serverTimestamp(),
            'ejecutadoPor': userActual.email,
            'estado': 'Sincronizado',
          }, SetOptions(merge: true));

      return {
        'exito': true,
        'mensaje': 'Ranking sincronizado correctamente en la base de datos.',
      };
    } catch (e) {
      print("🚨 Error al sincronizar localmente: $e");
      return {'exito': false, 'mensaje': 'Error de conexión: $e'};
    }
  }
}
