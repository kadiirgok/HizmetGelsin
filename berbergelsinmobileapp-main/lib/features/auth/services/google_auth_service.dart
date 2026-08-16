import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

abstract class IGoogleAuthService {
  Future<void> initialize();
  Future<GoogleAuthResult?> signIn();
  Future<String?> getFreshIdToken();
  Future<void> signOut();
}

class GoogleAuthResult {
  final String firebaseIdToken;
  final String? email;
  final String? displayName;

  const GoogleAuthResult({
    required this.firebaseIdToken,
    this.email,
    this.displayName,
  });
}

class GoogleAuthService implements IGoogleAuthService {
  static IGoogleAuthService instance = GoogleAuthService._();

  GoogleAuthService._();

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await GoogleSignIn.instance.initialize();
      _initialized = true;
      debugPrint('GoogleSignIn baslatildi.');
    } catch (e, stack) {
      debugPrint('GoogleSignIn baslatma HATASI: $e\n$stack');
    }
  }

  @override
  Future<GoogleAuthResult?> signIn() async {
    await initialize();

    try {
      debugPrint('GoogleSignIn: authenticate basliyor...');
      final googleUser = await GoogleSignIn.instance.authenticate();
      if (googleUser == null) {
        debugPrint('GoogleSignIn: kullanici null — iptal edildi.');
        return null;
      }

      debugPrint('GoogleSignIn: authentication aliniyor...');
      final googleAuth = await googleUser.authentication;
      final googleIdToken = googleAuth.idToken;

      debugPrint('GoogleSignIn: idToken var mi: ${googleIdToken != null}');

      if (googleIdToken == null || googleIdToken.isEmpty) {
        debugPrint('GoogleSignIn: idToken BOS! serverClientId gerekebilir.');
        await signOut();
        return null;
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleIdToken,
      );

      debugPrint('GoogleSignIn: Firebase signInWithCredential...');
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        debugPrint('GoogleSignIn: firebaseUser null!');
        await signOut();
        return null;
      }

      final firebaseIdToken = await firebaseUser.getIdToken(true);
      if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
        debugPrint('GoogleSignIn: firebaseIdToken BOS!');
        await signOut();
        return null;
      }

      debugPrint('GoogleSignIn: BASARILI!');
      return GoogleAuthResult(
        firebaseIdToken: firebaseIdToken,
        email: firebaseUser.email,
        displayName: firebaseUser.displayName,
      );
    } on FirebaseAuthException catch (e, stack) {
      debugPrint('GoogleSignIn Firebase HATA: ${e.code} ${e.message}\n$stack');
      await signOut();
      return null;
    } catch (e, stack) {
      debugPrint('GoogleSignIn HATA: ${e.runtimeType} $e\n$stack');
      await signOut();
      return null;
    }
  }

  @override
  Future<String?> getFreshIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken(true);
  }

  @override
  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    try {
      await initialize();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
