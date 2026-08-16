import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Phone Auth işlemlerini yöneten servis.
/// Android'de in-app reCAPTCHA kullanır (Chrome'a yönlendirmez).
class PhoneAuthService {
  static final PhoneAuthService instance = PhoneAuthService._();
  PhoneAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _verificationId;
  int? _resendToken;
  bool _languageSet = false;

  Future<void> _ensureLanguage() async {
    if (!_languageSet) {
      await _auth.setLanguageCode('tr');
      _languageSet = true;
    }
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(FirebaseAuthException) onError,
    Function(PhoneAuthCredential)? onAutoVerified,
  }) async {
    await _ensureLanguage();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        _verificationId = credential.verificationId;
        onAutoVerified?.call(credential);
      },
      verificationFailed: (e) => onError(e),
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> resendCode({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(FirebaseAuthException) onError,
  }) async {
    await _ensureLanguage();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (_) {},
      verificationFailed: (e) => onError(e),
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (_) {},
      forceResendingToken: _resendToken,
    );
  }

  Future<PhoneAuthResult> signInWithCode(String smsCode) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: smsCode,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    final firebaseIdToken = await userCredential.user!.getIdToken(true);
    return PhoneAuthResult(
      firebaseIdToken: firebaseIdToken!,
      phoneNumber: userCredential.user!.phoneNumber!,
    );
  }

  static String toE164(String turkishMobile) {
    final digits = turkishMobile.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90')) return '+$digits';
    return '+90$digits';
  }

  void reset() {
    _verificationId = null;
    _resendToken = null;
  }
}

class PhoneAuthResult {
  final String firebaseIdToken;
  final String phoneNumber;
  const PhoneAuthResult({
    required this.firebaseIdToken,
    required this.phoneNumber,
  });
}
