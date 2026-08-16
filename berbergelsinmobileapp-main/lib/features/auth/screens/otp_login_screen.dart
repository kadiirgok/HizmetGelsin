import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import '../../../core/theme/app_theme.dart';
import '../../onboarding/widgets/kvkk_sheet.dart';
import '../bloc/auth_cubit.dart';
import '../services/google_auth_service.dart';
import '../widgets/auth_widgets.dart';

typedef GoogleLoginRunner = Future<GoogleLoginResponse?> Function();

class OtpLoginScreen extends StatefulWidget {
  const OtpLoginScreen({
    super.key,
    this.googleLogin,
    this.onGooglePhoneRequired,
  });

  final GoogleLoginRunner? googleLogin;
  final VoidCallback? onGooglePhoneRequired;

  @override
  State<OtpLoginScreen> createState() => _OtpLoginScreenState();
}

class _OtpLoginScreenState extends State<OtpLoginScreen> {
  bool _loading = false;
  bool _codeSent = false;
  final _emailController = TextEditingController();
  String _code = '';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Lütfen geçerli bir e-posta adresi girin.');
      return;
    }
    
    setState(() => _loading = true);
    try {
      await context.read<AuthCubit>().sendEmailOtp(email);
      setState(() {
        _codeSent = true;
      });
    } catch (e) {
      _showError('Kod gönderilemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_code.length < 6) {
      _showError('Lütfen 6 haneli kodu girin.');
      return;
    }

    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim();
      final response = await context.read<AuthCubit>().verifyEmailOtp(email, _code);
      
      if (!mounted) return;
      if (response.phoneVerificationRequired) {
        if (widget.onGooglePhoneRequired != null) {
          widget.onGooglePhoneRequired!();
        } else {
          context.push('/google-telefon-dogrulama', extra: {'email': email, 'code': _code});
        }
      } else if (response.error != null) {
        _showError(response.error!);
      }
    } catch (_) {
      _showError('Doğrulama işlemi başarısız oldu.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      GoogleLoginResponse? response;
      final runner = widget.googleLogin;
      if (runner != null) {
        response = await runner();
      } else {
        final authResult = await GoogleAuthService.instance.signIn();
        if (authResult == null || authResult.firebaseIdToken.isEmpty) return;
        if (!mounted) return;
        response = await context.read<AuthCubit>().loginWithGoogle(
          authResult.firebaseIdToken,
        );
      }

      if (!mounted || response == null) return;
      if (response.phoneVerificationRequired) {
        if (widget.onGooglePhoneRequired != null) {
          widget.onGooglePhoneRequired!();
        } else {
          context.push('/google-telefon-dogrulama');
        }
      } else if (response.error != null) {
        _showError(response.error!);
      }
    } catch (_) {
      if (mounted) {
        _showError('Google girişi tamamlanamadı. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Geri',
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _loading ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: AuthPageBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthBrandHeader(showName: false, logoSize: 64),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Giriş yap veya kayıt ol',
                style: AppTypography.headline,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'E-posta adresinizle giriş yapın veya kayıt olun.',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              
              if (!_codeSent) ...[
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-posta Adresi',
                    hintText: 'ornek@mail.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_loading,
                ),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: _loading ? null : _sendCode,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Devam Et', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ] else ...[
                Text(
                  '${_emailController.text} adresine gönderilen 6 haneli kodu girin.',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                Pinput(
                  length: 6,
                  keyboardType: TextInputType.number,
                  onChanged: (val) => _code = val,
                  onCompleted: (_) => _verifyCode(),
                  defaultPinTheme: PinTheme(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                  ),
                  focusedPinTheme: PinTheme(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: _loading ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Doğrula', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
              
              const SizedBox(height: AppSpacing.xxl),
              
              OutlinedButton(
                key: const Key('google_login_button'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: AppColors.border),
                ),
                onPressed: _loading ? null : _loginWithGoogle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/google_logo.png',
                      width: 24,
                      height: 24,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Flexible(
                      child: Text(
                        'Google ile Devam Et',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: AppSpacing.xxl),
              Semantics(
                button: true,
                link: true,
                label: 'Kullanım Koşulları ve KVKK metnini aç',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: InkWell(
                    onTap: () => showKvkkSheet(context),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text.rich(
                        TextSpan(
                          text: 'Devam ederek ',
                          children: [
                            TextSpan(
                              text: 'Kullanım Koşulları ve KVKK Metnini',
                              style: TextStyle(
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            TextSpan(text: ' kabul etmiş olursunuz.'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
