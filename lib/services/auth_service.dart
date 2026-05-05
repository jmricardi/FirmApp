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
      await _auth.signInWithEmailAndPassword(email: email, password: password);
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
      debugPrint('Intentando crear/verificar documento para UID: ${user.uid}');
      final docRef = _db.collection('users').doc(user.uid);
      final doc = await docRef.get().timeout(const Duration(seconds: 10));
      
      final bool docExists = doc.exists;
      final Map<String, dynamic>? data = docExists ? (doc.data() as Map<String, dynamic>?) : null;
      
      // Si el documento no existe, o le faltan campos críticos (como email o créditos), inicializamos/reparamos
      if (!docExists || data == null || !data.containsKey('credits') || !data.containsKey('email')) {
        debugPrint('Inicializando o reparando documento de usuario...');
        final packageInfo = await PackageInfo.fromPlatform();
        
        final Map<String, dynamic> userData = {
          'email': user.email ?? data?['email'] ?? '',
          'displayName': initialName ?? user.displayName ?? data?['displayName'] ?? 'Usuario',
          'credits': data?['credits'] ?? 5, // Preservamos créditos si ya existían, sino 5
          'app_version': packageInfo.version,
          'force_update_to': data?['force_update_to'] ?? '',
          'lastActive': FieldValue.serverTimestamp(),
        };

        if (!docExists) {
          userData['createdAt'] = FieldValue.serverTimestamp();
        }

        await docRef.set(userData, SetOptions(merge: true));
        
        // Registramos en el historial de D1 a través del worker
        try {
          // Usamos 'log' para registrar la entrada sin intentar actualizar Firestore (ya lo hicimos arriba)
          http.get(
            Uri.parse('https://easyscan-credits-worker.jmricardi-3d1.workers.dev?action=log&uid=${user.uid}&amount=5&desc=Regalo%20de%20Bienvenida'),
            headers: {'Authorization': 'SuperEasyScan2024'},
          );
        } catch (e) {
          debugPrint('Error al registrar historial de bienvenida: $e');
        }
        
        debugPrint('¡Documento de usuario creado con éxito!');
      } else {
        debugPrint('El usuario ya existe en Firestore.');
      }
    } catch (e) {
      debugPrint('FATAL: Error al conectar con Firestore: $e');
      // Si el error contiene "permission-denied", es que las reglas fallaron
      // Si el error contiene "API Key", es que el google-services.json está mal
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
