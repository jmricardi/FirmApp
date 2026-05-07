import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      await _ensureUserDocument(userCredential.user!);
    } catch (e) {
      debugPrint('Error en Google Sign In: $e');
      rethrow;
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      if (credential.user != null) {
        await _ensureUserDocument(credential.user!);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') throw 'No existe una cuenta con este email.';
      if (e.code == 'wrong-password') throw 'Contraseña incorrecta.';
      rethrow;
    }
  }

  Future<void> registerWithEmail(String email, String password, String displayName) async {
    try {
      final UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email, 
        password: password,
      );
      await credential.user!.updateDisplayName(displayName);
      await _ensureUserDocument(credential.user!, initialName: displayName);
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
      if (e.code == 'user-not-found') throw 'No hay ninguna cuenta con este email.';
      rethrow;
    }
  }

  Future<void> _ensureUserDocument(User user, {String? initialName}) async {
    try {
      debugPrint('Verificando perfil Firestore para UID: ${user.uid}');
      final docRef = _db.collection('users').doc(user.uid);
      final doc = await docRef.get().timeout(const Duration(seconds: 10));
      
      final packageInfo = await PackageInfo.fromPlatform();
      final bool docExists = doc.exists;
      final Map<String, dynamic>? data = docExists ? (doc.data() as Map<String, dynamic>?) : null;

      // 1. Datos base que SIEMPRE se actualizan (Conexión, Versión)
      final Map<String, dynamic> updates = {
        'lastActive': FieldValue.serverTimestamp(),
        'app_version': packageInfo.version,
        'email': user.email ?? data?['email'] ?? '',
      };

      // 2. Si el documento NO existe, inicializamos valores de bienvenida
      if (!docExists || data == null || !data.containsKey('credits')) {
        debugPrint('Inicializando nuevo perfil de usuario con créditos de bienvenida...');
        
        updates['createdAt'] = data?['createdAt'] ?? FieldValue.serverTimestamp();
        updates['displayName'] = initialName ?? user.displayName ?? data?['displayName'] ?? 'Usuario';
        
        // Solo damos créditos si realmente no tiene el campo (evita duplicar en login)
        if (data == null || !data.containsKey('credits')) {
          updates['credits'] = 5;
          updates['total_spent'] = 0;
          updates['total_earned'] = 5;

          // Registro en historial externo (Worker D1)
          try {
            await http.get(
              Uri.parse('https://easyscan-credits-worker.jmricardi-3d1.workers.dev?action=log&uid=${user.uid}&amount=5&desc=Regalo%20de%20Bienvenida'),
              headers: {'Authorization': 'SuperEasyScan2024'},
            ).timeout(const Duration(seconds: 10));
            debugPrint('Historial de bienvenida registrado en D1.');
          } catch (e) {
            debugPrint('Aviso: No se pudo registrar en historial D1: $e');
          }
        }
      }

      // 3. Guardar/Actualizar en Firestore
      await docRef.set(updates, SetOptions(merge: true));
      debugPrint('Perfil actualizado/verificado con éxito en Firestore.');

    } catch (e) {
      debugPrint('ERROR CRÍTICO en _ensureUserDocument: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
