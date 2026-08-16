import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/widgets/kvkk_sheet.dart';
import '../bloc/auth_cubit.dart';
import '../services/google_auth_service.dart';
import '../widgets/auth_widgets.dart';

class PasswordLoginScreen extends StatefulWidget {
  const PasswordLoginScreen({super.key});

  @override
  State<PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends State<PasswordLoginScreen> {
  bool _loading = false;
  bool _obscurePassword = true;
  final _credentialController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _credentialController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final credential = _credentialController.text.trim();
    final password = _passwordController.text;

    if (credential.isEmpty) {
      setState(() => _error = 'E-posta veya telefon numarası girin.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Şifre girin.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final result = await context.read<AuthCubit>().login(
      credential: credential,
      password: password,
    );

    if (!mounted) return;
    if (result.error != null) {
      setState(() { _loading = false; _error = result.error; });
    }
  }

  void _showForgotPassword() {
    final emailCtrl = TextEditingController();
    String? error;
    bool loading = false;
    bool codeSent = false;
    final codeCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Şifre Sıfırlama',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Email adresinize sıfırlama kodu gönderilecek.',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              if (!codeSent) ...[
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email adresiniz',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: loading ? null : () async {
                    if (emailCtrl.text.trim().isEmpty) {
                      setState(() => error = 'Email adresinizi girin.');
                      return;
                    }
                    setState(() { loading = true; error = null; });
                    try {
                      await context.read<AuthCubit>().sendForgotPassword(emailCtrl.text.trim());
                      setState(() { loading = false; codeSent = true; });
                    } on ApiException catch (e) {
                      setState(() { loading = false; error = e.message; });
                    } catch (_) {
                      setState(() { loading = false; error = 'Kod gönderilemedi.'; });
                    }
                  },
                  child: Text(loading ? 'Gönderiliyor...' : 'Sıfırlama Kodu Gönder'),
                ),
              ] else ...[
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '6 haneli kod',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Yeni şifre (en az 8 karakter)',
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: loading ? null : () async {
                    if (codeCtrl.text.length < 6) {
                      setState(() => error = '6 haneli kodu girin.');
                      return;
                    }
                    if (newPassCtrl.text.length < 8) {
                      setState(() => error = 'Yeni şifre en az 8 karakter olmalı.');
                      return;
                    }
                    setState(() { loading = true; error = null; });
                    try {
                      await context.read<AuthCubit>().resetPassword(
                        emailCtrl.text.trim(), codeCtrl.text.trim(), newPassCtrl.text,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Şifreniz sıfırlandı. Yeni şifrenizle giriş yapın.'),
                            backgroundColor: AppColors.success),
                      );
                    } on ApiException catch (e) {
                      setState(() { loading = false; error = e.message; });
                    } catch (_) {
                      setState(() { loading = false; error = 'Şifre sıfırlanamadı.'; });
                    }
                  },
                  child: Text(loading ? 'Sıfırlanıyor...' : 'Şifreyi Sıfırla'),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 13),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _loading = true);
    try {
      // Önce Google Sign-In ile kimlik doğrula
      final authResult = await GoogleAuthService.instance.signIn();
      if (authResult == null || authResult.firebaseIdToken.isEmpty) {
        if (mounted) {
          setState(() { _loading = false; _error = 'Google kimlik bilgisi alınamadı.'; });
        }
        return;
      }

      if (!mounted) return;
      final result = await context.read<AuthCubit>().loginWithGoogle(authResult.firebaseIdToken);

      if (!mounted) return;
      if (result.error != null) {
        setState(() { _loading = false; _error = result.error; });
      } else if (result.phoneVerificationRequired) {
        context.push('/google-telefon-dogrulama');
      }
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _error = 'Google girişi başarısız oldu.'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                const AuthBrandHeader(showName: true, logoSize: 80),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Hoş geldiniz',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Devam etmek için giriş yapın',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Credential
                TextField(
                  controller: _credentialController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  enabled: !_loading,
                  decoration: InputDecoration(
                    labelText: 'E-posta veya Telefon',
                    hintText: 'ornek@email.com / 5XX XXX XX XX',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Password
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  enabled: !_loading,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showForgotPassword(),
                    child: const Text('Şifremi unuttum', style: TextStyle(fontSize: 13)),
                  ),
                ),

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Login button
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Giriş Yap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 20),

                // Divider
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('veya', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),

                // Google
                OutlinedButton.icon(
                  onPressed: _loading ? null : _loginWithGoogle,
                  icon: Image.asset('assets/google_g.png', height: 22,
                      errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 24)),
                  label: const Text('Google ile Devam Et'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 28),

                // Register
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Hesabınız yok mu?', style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(
                      onPressed: () => context.push('/kayit-ol'),
                      child: const Text('Kayıt olun', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),

                // KVKK
                GestureDetector(
                  onTap: () => showKvkkSheet(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Devam ederek KVKK ve Kullanım Koşullarını\nkabul etmiş olursunuz.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
