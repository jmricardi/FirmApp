import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
      
      if (!doc.exists) {
        debugPrint('El usuario no existe en Firestore. Creando...');
        await docRef.set({
          'email': user.email,
          'displayName': initialName ?? user.displayName,
          'credits': 5,
          'createdAt': FieldValue.serverTimestamp(),
        });
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
