import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  static const String _workerUrl =
      'https://firmapp-credits-worker.jmricardi-3d1.workers.dev';

  User? get currentUser => _auth.currentUser;

  AuthService() {
    _auth.authStateChanges().listen((user) {
      notifyListeners();
    });
  }

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      await _ensureUserDocument(userCredential.user!);
    } catch (e) {
      debugPrint('Error en Google Sign In: $e');
      rethrow;
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      if (credential.user != null) {
        if (!credential.user!.emailVerified) {
          await _auth.signOut();
          throw 'Debes verificar tu email antes de ingresar. Revisa tu bandeja de entrada.';
        }
        await _ensureUserDocument(credential.user!);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found')
        throw 'No existe una cuenta con este email.';
      if (e.code == 'wrong-password') throw 'Contraseña incorrecta.';
      rethrow;
    }
  }

  Future<void> registerWithEmail(
      String email, String password, String displayName) async {
    try {
      final UserCredential credential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user!.updateDisplayName(displayName);
      await credential.user!.sendEmailVerification();
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw 'Este email ya está registrado. Intenta iniciar sesión.';
      }
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found')
        throw 'No hay ninguna cuenta con este email.';
      rethrow;
    }
  }

  Future<void> _ensureUserDocument(User user, {String? initialName}) async {
    try {
      debugPrint('Sincronizando perfil con Worker para UID: ${user.uid}');

      final packageInfo = await PackageInfo.fromPlatform();
      final prefs = await SharedPreferences.getInstance();

      // Leer version_hash local (para Optimistic Locking)
      final localVersionHash = prefs.getString('profile_version_hash_${user.uid}');

      // Obtener idToken de Firebase para autenticación en el Worker
      final idToken = await user.getIdToken();

      // Detectar si es registro nuevo o login
      final action = initialName != null ? 'initialize_user' : 'sync_profile';
      final displayName = initialName ?? user.displayName ?? 'Usuario';

      debugPrint('Acción a ejecutar: $action');

      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': action,
          'email': user.email ?? '',
          'displayName': displayName,
          'app_version': packageInfo.version,
          if (localVersionHash != null) 'version_hash': localVersionHash,
        }),
      ).timeout(const Duration(seconds: 15));

      debugPrint('Worker Response [$action]: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        // Éxito: guardar nuevo version_hash y updated_at en caché local
        final decoded = jsonDecode(response.body);
        final userData = decoded['data']?['user'];
        if (userData != null) {
          if (userData['version_hash'] != null) {
            await prefs.setString(
                'profile_version_hash_${user.uid}', userData['version_hash']);
          }
          if (userData['updated_at'] != null) {
            await prefs.setString(
                'profile_updated_at_${user.uid}', userData['updated_at']);
          }
        }
        debugPrint('Perfil sincronizado con éxito en Worker.');

        // Mantener lógica de referido pendiente (solo si ya existe el usuario)
        if (action == 'sync_profile') {
          if (prefs.containsKey('pending_referral')) {
            await prefs.remove('pending_referral');
            debugPrint('Referido pendiente eliminado: Usuario ya existente.');
          }
        }

      } else if (response.statusCode == 409) {
        // Conflicto: el servidor tiene una versión más nueva del perfil
        // Prioridad al servidor: actualizar caché local con los datos del servidor
        debugPrint('CONFLICT 409: Actualizando caché local con datos del servidor...');
        final decoded = jsonDecode(response.body);
        final serverUser = decoded['data']?['user'];
        if (serverUser != null) {
          if (serverUser['version_hash'] != null) {
            await prefs.setString(
                'profile_version_hash_${user.uid}', serverUser['version_hash']);
          }
          if (serverUser['updated_at'] != null) {
            await prefs.setString(
                'profile_updated_at_${user.uid}', serverUser['updated_at']);
          }
          debugPrint('Caché local actualizada con versión del servidor (resolución de conflicto).');
        }

      } else {
        debugPrint('Error del Worker: ${response.statusCode} - ${response.body}');
      }

    } catch (e) {
      // En caso de error de red, la app continúa. No es un error crítico.
      debugPrint('ERROR en _ensureUserDocument (Worker): $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
