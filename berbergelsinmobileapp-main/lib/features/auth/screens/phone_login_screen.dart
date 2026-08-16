import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/widgets/kvkk_sheet.dart';
import '../bloc/auth_cubit.dart';
import '../services/google_auth_service.dart';
import '../services/phone_auth_service.dart';
import '../services/sms_rate_limiter.dart';
import '../widgets/auth_widgets.dart';

typedef GoogleLoginRunner = Future<GoogleLoginResponse?> Function();

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({
    super.key,
    this.googleLogin,
  });

  final GoogleLoginRunner? googleLogin;

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  bool _loading = false;
  bool _codeSent = false;
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String _displayPhone = '';

  // ── Rate limit / cooldown ──
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  bool _rateLimited = false; // saatlik limit dolduğunda true

  @override
  void initState() {
    super.initState();
    _checkInitialCooldown();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _cooldownTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ── Cooldown timer ──────────────────────────────────────────────

  Future<void> _checkInitialCooldown() async {
    final result = await SmsRateLimiter.instance.checkCanSend();
    if (!mounted) return;
    if (!result.canSend) {
      _startCooldown(result.waitSeconds);
      if (result.waitSeconds > 300) {
        setState(() => _rateLimited = true);
      }
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSeconds > 0) {
          _cooldownSeconds--;
        }
        if (_cooldownSeconds <= 0) {
          timer.cancel();
          _cooldownSeconds = 0;
          _rateLimited = false;
        }
      });
    });
  }

  void _applyRateLimitResult(SmsRateLimitResult result) {
    if (result.canSend) return;
    _startCooldown(result.waitSeconds);
    if (result.waitSeconds > 300) {
      setState(() => _rateLimited = true);
    }
    _showError(result.reason);
  }

  String get _cooldownText {
    if (_cooldownSeconds <= 0) return '';
    final m = _cooldownSeconds ~/ 60;
    final s = _cooldownSeconds % 60;
    if (m > 0) {
      return '$m dk $s sn sonra tekrar deneyin';
    }
    return '$s sn sonra tekrar deneyin';
  }

  // ── UI helpers ──────────────────────────────────────────────────

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
  }

  void _showWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.warning,
        ),
      );
  }

  // ── SMS gönderme ────────────────────────────────────────────────

  Future<void> _sendCode() async {
    final rateCheck = await SmsRateLimiter.instance.checkCanSend();
    if (!rateCheck.canSend) {
      _applyRateLimitResult(rateCheck);
      return;
    }

    final rawPhone = _phoneController.text.trim();
    if (rawPhone.length < 10) {
      _showError('Lütfen geçerli bir telefon numarası girin.');
      return;
    }

    final normalizedPhone = normalizeTurkishMobile(rawPhone);
    if (!isValidTurkishMobile(normalizedPhone)) {
      _showError('Lütfen 5 ile başlayan geçerli bir cep telefonu girin.');
      return;
    }

    setState(() {
      _loading = true;
      _displayPhone = rawPhone;
    });

    try {
      // Firebase Phone Auth ile SMS gönder
      final e164 = PhoneAuthService.toE164(normalizedPhone);
      await PhoneAuthService.instance.verifyPhoneNumber(
        phoneNumber: e164,
        onCodeSent: (verificationId, resendToken) {
          if (mounted) {
            SmsRateLimiter.instance.recordRequest();
            setState(() { _codeSent = true; _loading = false; });
          }
        },
        onError: (e) {
          if (mounted) { setState(() => _loading = false); _showError(e.message ?? 'SMS gönderilemedi.'); }
        },
        onAutoVerified: (credential) async {
          try {
            final uc = await FirebaseAuth.instance.signInWithCredential(credential);
            final token = await uc.user!.getIdToken(true);
            if (mounted) await context.read<AuthCubit>().loginWithPhone(token!, e164);
          } catch (e) {
            if (mounted) { setState(() => _loading = false); _showError('Otomatik doğrulama başarısız.'); }
          }
        },
      );
    } catch (e) {
      if (mounted) { setState(() => _loading = false); _showError('SMS gönderilemedi.'); }
    }
  }

  // ── Kod doğrulama ───────────────────────────────────────────────

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length < 6) { _showError('6 haneli kodu girin.'); return; }
    setState(() => _loading = true);
    try {
      final result = await PhoneAuthService.instance.signInWithCode(code);
      final normalizedPhone = normalizeTurkishMobile(_phoneController.text.trim());
      if (!mounted) return;
      await context.read<AuthCubit>().loginWithPhone(result.firebaseIdToken, '+90$normalizedPhone');
    } on FirebaseAuthException catch (e) {
      if (mounted) { setState(() => _loading = false); _showError(e.message ?? 'Geçersiz kod.'); }
    } on ApiException catch (e) {
      if (mounted) { setState(() => _loading = false); _showError(e.message); }
    } catch (e) {
      if (mounted) { setState(() => _loading = false); _showError('Giriş yapılamadı.'); }
    }
  }

  // ── Google giriş ────────────────────────────────────────────────

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
        if (authResult == null || authResult.firebaseIdToken.isEmpty) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        if (!mounted) return;
        response = await context.read<AuthCubit>().loginWithGoogle(
              authResult.firebaseIdToken,
            );
      }

      if (!mounted || response == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (response.error != null) {
        _showError(response.error!);
      }
    } catch (_) {
      if (mounted) {
        _showError('Google girişi tamamlanamadı.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Email alternatifi ───────────────────────────────────────────

  Future<void> _switchToEmail() async {
    if (!mounted) return;
    final router = GoRouter.of(context);
    router.push('/email-giris', extra: {
      'googleLogin': widget.googleLogin,
    });
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isCooldown = _cooldownSeconds > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Geri',
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed:
              _loading ? null : () => Navigator.of(context).maybePop(),
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
                'Telefon numaranızla giriş yapın veya kayıt olun.',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              if (!_codeSent) ...[
                AuthPhoneField(
                  controller: _phoneController,
                  enabled: !_loading && !isCooldown,
                  autofocus: true,
                  onSubmitted: (_) => _sendCode(),
                ),
                const SizedBox(height: AppSpacing.lg),
                // ── SMS gönder butonu / cooldown ──
                if (isCooldown)
                  _CooldownButton(cooldownText: _cooldownText)
                else
                  ElevatedButton(
                    onPressed: _loading ? null : _sendCode,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _loading
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text('Devam Et',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                // ── Rate limit uyarısı + email alternatifi ──
                if (_rateLimited) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _RateLimitBanner(onEmailTap: _switchToEmail),
                ],
              ] else ...[
                // ── Kod giriş ekranı ──
                Text(
                  '$_displayPhone numarasına gönderilen\n6 haneli kodu girin.',
                  style: AppTypography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                ResponsiveOtpField(
                  controller: _codeController,
                  enabled: !_loading,
                  onCompleted: (_) => _verifyCode(),
                ),
                const SizedBox(height: AppSpacing.md),
                // ── Tekrar gönder / cooldown ──
                if (isCooldown)
                  _CooldownTextButton(cooldownText: _cooldownText)
                else
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            _codeController.clear();
                            _sendCode();
                          },
                    child: const Text('Kodu tekrar gönder'),
                  ),
                const SizedBox(height: AppSpacing.sm),
                ElevatedButton(
                  onPressed: _loading ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('Doğrula',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              OutlinedButton(
                key: const Key('email_login_button'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: AppColors.border),
                ),
                onPressed: _loading ? null : _switchToEmail,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.email_outlined, size: 24),
                    const SizedBox(width: AppSpacing.md),
                    const Flexible(
                      child: Text(
                        'E-posta ile Devam Et',
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
                              text:
                                  'Kullanım Koşulları ve KVKK Metnini',
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

// ── Cooldown Widget'ları ──────────────────────────────────────────────

/// SMS gönderme butonu yerine gösterilen cooldown butonu.
class _CooldownButton extends StatelessWidget {
  const _CooldownButton({required this.cooldownText});

  final String cooldownText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.disabled.withAlpha(51),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.textSecondary, size: 20),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            cooldownText,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Kod giriş ekranındaki "tekrar gönder" yerine cooldown text.
class _CooldownTextButton extends StatelessWidget {
  const _CooldownTextButton({required this.cooldownText});

  final String cooldownText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            cooldownText,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rate limit uyarı kartı — email alternatifi ile birlikte.
class _RateLimitBanner extends StatelessWidget {
  const _RateLimitBanner({required this.onEmailTap});

  final VoidCallback onEmailTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(25),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withAlpha(76)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'SMS limitine ulaşıldı. Lütfen bir süre bekleyin.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEmailTap,
              icon: const Icon(Icons.email_outlined, size: 18),
              label: const Text('Email ile doğrula'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
