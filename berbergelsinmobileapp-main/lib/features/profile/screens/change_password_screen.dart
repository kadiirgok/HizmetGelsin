import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Oturum açmış kullanıcının şifresini değiştirme sayfası.
/// Firebase Auth üzerinden reauthenticate + updatePassword kullanır.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _busy = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String? _error;

  bool get _canSubmit =>
      _currentPassword.text.isNotEmpty &&
      _newPassword.text.isNotEmpty &&
      _confirmPassword.text.isNotEmpty &&
      !_busy;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _error = 'Yeni şifre ve onayı eşleşmiyor.');
      return;
    }
    if (_newPassword.text.length < 6) {
      setState(() => _error = 'Yeni şifre en az 6 karakter olmalı.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(
        () => _error = 'Oturum bulunamadı. Lütfen tekrar giriş yapın.',
      );
      return;
    }
    if (user.email == null) {
      setState(
        () => _error =
            'Bu hesap e-posta ile giriş yapmadığı için şifre değiştirilemez.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // Re-authenticate with current password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPassword.text,
      );
      await user.reauthenticateWithCredential(credential);
      // Update password
      await user.updatePassword(_newPassword.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Şifreniz başarıyla değiştirildi.'),
            backgroundColor: Colors.green,
          ),
        );
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'wrong-password' ||
        'invalid-credential' =>
          'Mevcut şifre yanlış.',
        'too-many-requests' => 'Çok fazla deneme yaptınız. Lütfen bekleyin.',
        'requires-recent-login' =>
          'Güvenlik nedeniyle tekrar giriş yapmanız gerekiyor.',
        _ => 'Şifre değiştirilemedi. Lütfen tekrar deneyin.',
      };
      setState(() => _error = message);
    } catch (_) {
      setState(() => _error = 'Bir hata oluştu. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Şifre Değiştir')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Bilgi kartı
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Güvenliğiniz için mevcut şifrenizi girmeniz gerekmektedir. '
                    'Yeni şifreniz en az 6 karakter olmalıdır.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Mevcut şifre
          TextField(
            controller: _currentPassword,
            obscureText: _obscureCurrent,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Mevcut Şifre',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCurrent ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Yeni şifre
          TextField(
            controller: _newPassword,
            obscureText: _obscureNew,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Yeni Şifre',
              prefixIcon: const Icon(Icons.lock_outlined),
              helperText: 'En az 6 karakter',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Yeni şifre tekrar
          TextField(
            controller: _confirmPassword,
            obscureText: _obscureConfirm,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _canSubmit ? _submit() : null,
            decoration: InputDecoration(
              labelText: 'Yeni Şifre (Tekrar)',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Şifreyi Değiştir'),
            ),
          ),
        ],
      ),
    );
  }
}
