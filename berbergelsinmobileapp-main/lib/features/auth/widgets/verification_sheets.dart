import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_ui.dart';
import '../bloc/auth_cubit.dart';
import '../models/app_user.dart';
import '../services/phone_auth_service.dart';
import 'auth_widgets.dart';

/// Doğrulama bottom sheet'leri.
class VerificationSheets {
  const VerificationSheets._();

  /// Telefon doğrulama — Firebase Phone Auth.
  static void showPhoneVerification(BuildContext context, AppUser? user) {
    String? error;
    bool loading = false;
    bool codeSent = false;
    final codeController = TextEditingController();
    final phoneNumber = user?.phone ?? '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AppBottomSheet(
          title: 'Telefon doğrulama',
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_maskPhone(phoneNumber)} numarasına\nFirebase SMS gönderilecek.',
                    style: AppTypography.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                if (!codeSent)
                  PrimaryButton(
                    label: loading ? 'Gönderiliyor...' : 'SMS Doğrulama Kodu Gönder',
                    icon: Icons.sms_outlined,
                    onPressed: loading ? null : () async {
                      setSheetState(() { loading = true; error = null; });
                      final e164 = PhoneAuthService.toE164(normalizeTurkishMobile(phoneNumber));
                      try {
                        await PhoneAuthService.instance.verifyPhoneNumber(
                          phoneNumber: e164,
                          onCodeSent: (_, __) => setSheetState(() { loading = false; codeSent = true; }),
                          onError: (e) => setSheetState(() { loading = false; error = e.message ?? 'SMS gönderilemedi.'; }),
                          onAutoVerified: (credential) async {
                            try {
                              final uc = await FirebaseAuth.instance.signInWithCredential(credential);
                              final token = await uc.user!.getIdToken(true);
                              if (!ctx.mounted) return;
                              final err = await context.read<AuthCubit>().verifyPhoneWithFirebase(token!);
                              if (!ctx.mounted) return;
                              if (err != null) { setSheetState(() => error = err); }
                              else { Navigator.pop(ctx); _showSuccess(context, 'Telefon numaranız'); }
                            } catch (_) { setSheetState(() => error = 'Otomatik doğrulama başarısız.'); }
                          },
                        );
                      } catch (_) { setSheetState(() { loading = false; error = 'SMS gönderilemedi.'; }); }
                    },
                  ),
                if (codeSent) ...[
                  ResponsiveOtpField(
                    controller: codeController, enabled: !loading,
                    onCompleted: (_) => _verifyPhone(ctx, setSheetState, codeController, context),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: loading ? null : () {
                      codeController.clear();
                      setSheetState(() { loading = true; error = null; });
                      final e164 = PhoneAuthService.toE164(normalizeTurkishMobile(phoneNumber));
                      PhoneAuthService.instance.resendCode(
                        phoneNumber: e164,
                        onCodeSent: (_, __) => setSheetState(() => loading = false),
                        onError: (e) => setSheetState(() { loading = false; error = 'Tekrar gönderilemedi: ${e.message}'; }),
                      );
                    },
                    child: const Text('Kodu tekrar gönder'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: loading ? 'Doğrulanıyor...' : 'Doğrula',
                    onPressed: loading ? null : () =>
                        _verifyPhone(ctx, setSheetState, codeController, context),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 13),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _verifyPhone(BuildContext ctx, void Function(void Function()) ss,
      TextEditingController ctrl, BuildContext outer) async {
    final code = ctrl.text.trim();
    if (code.length < 6) return;
    try {
      final result = await PhoneAuthService.instance.signInWithCode(code);
      final err = await outer.read<AuthCubit>().verifyPhoneWithFirebase(result.firebaseIdToken);
      if (!ctx.mounted) return;
      if (err != null) { ss(() {}); }
      else { Navigator.pop(ctx); _showSuccess(outer, 'Telefon numaranız'); }
    } on FirebaseAuthException catch (e) { ss(() {}); }
    on ApiException catch (e) { ss(() {}); }
    catch (_) { ss(() {}); }
  }

  /// E-posta doğrulama
  static void showEmailVerification(BuildContext context, AppUser? user) {
    String? error;
    bool loading = false;
    bool codeSent = false;
    final codeController = TextEditingController();

    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AppBottomSheet(
          title: 'E-posta doğrulama',
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
              children: [
                Text('${user?.email ?? ""} adresine\ndoğrulama kodu gönderilecek.',
                    style: AppTypography.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                if (!codeSent)
                  PrimaryButton(
                    label: loading ? 'Gönderiliyor...' : 'Doğrulama Kodu Gönder',
                    icon: Icons.email_outlined,
                    onPressed: loading ? null : () async {
                      setSheetState(() { loading = true; error = null; });
                      try {
                        await context.read<AuthCubit>().sendEmailVerification();
                        setSheetState(() { loading = false; codeSent = true; });
                      } on ApiException catch (e) { setSheetState(() { loading = false; error = e.message; }); }
                      catch (_) { setSheetState(() { loading = false; error = 'Kod gönderilemedi.'; }); }
                    },
                  ),
                if (codeSent) ...[
                  ResponsiveOtpField(
                    controller: codeController, enabled: !loading,
                    onCompleted: (_) => _verifyEmail(ctx, setSheetState, codeController, context),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: loading ? 'Doğrulanıyor...' : 'Doğrula',
                    onPressed: loading ? null : () => _verifyEmail(ctx, setSheetState, codeController, context),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 13),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _verifyEmail(BuildContext ctx, void Function(void Function()) ss,
      TextEditingController ctrl, BuildContext outer) async {
    final code = ctrl.text.trim();
    if (code.length < 6) return;
    final err = await outer.read<AuthCubit>().verifyEmail(code);
    if (!ctx.mounted) return;
    if (err != null) { ss(() {}); }
    else { Navigator.pop(ctx); _showSuccess(outer, 'E-posta adresiniz'); }
  }

  static void _showSuccess(BuildContext context, String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$label doğrulandı.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
  }

  static String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return '••••';
    return '${digits.substring(0, 2)}•• ••• •• ${digits.substring(digits.length - 2)}';
  }
}
