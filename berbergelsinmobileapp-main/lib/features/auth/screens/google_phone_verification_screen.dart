import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/auth_cubit.dart';
import '../services/google_auth_service.dart';
import '../widgets/auth_widgets.dart';

class GooglePhoneVerificationScreen extends StatefulWidget {
  const GooglePhoneVerificationScreen({
    super.key,
    this.cancelTemporarySession,
    this.emailForVerification,
    this.codeForVerification,
  });

  final Future<void> Function()? cancelTemporarySession;
  final String? emailForVerification;
  final String? codeForVerification;

  @override
  State<GooglePhoneVerificationScreen> createState() =>
      _GooglePhoneVerificationScreenState();
}

class _GooglePhoneVerificationScreenState
    extends State<GooglePhoneVerificationScreen> {
  final _phone = TextEditingController();

  bool _saving = false;
  bool _allowPop = false;
  String? _phoneError;
  String? _requestError;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _savePhone() async {
    if (_saving) return;
    final phone = normalizeTurkishMobile(_phone.text);
    if (!isValidTurkishMobile(phone)) {
      setState(() {
        _phoneError = '5 ile başlayan 10 haneli bir cep telefonu girin.';
        _requestError = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _phoneError = null;
      _requestError = null;
    });
    
    try {
      if (widget.emailForVerification != null && widget.codeForVerification != null) {
        final response = await context.read<AuthCubit>().verifyEmailOtp(
          widget.emailForVerification!,
          widget.codeForVerification!,
          phone,
        );
        if (response.error != null) {
          if (mounted) setState(() => _requestError = response.error);
        }
      } else {
        await context.read<AuthCubit>().saveGooglePhone(phone: phone);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _requestError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _requestError = 'Kaydetme işlemi başarısız. Lütfen tekrar deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    if (_saving) return;
    final cancel = widget.cancelTemporarySession;
    if (cancel != null) {
      await cancel();
    } else {
      await GoogleAuthService.instance.signOut();
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _cancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            key: const Key('google_phone_back_button'),
            tooltip: 'Geri',
            onPressed: _saving ? null : _cancel,
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          ),
          title: const Text('İletişim Numarası'),
        ),
        body: SafeArea(
          child: AuthPageBody(
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthBrandHeader(showName: false, logoSize: 64),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'İletişim Numarası',
                    style: AppTypography.headline,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Berberlerin size ulaşabilmesi için lütfen telefon numaranızı girin. (SMS Onayı Gerekmez)',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  AuthPhoneField(
                    controller: _phone,
                    enabled: !_saving,
                    errorText: _phoneError ?? _requestError,
                    onSubmitted: (_) => _savePhone(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  LoadingPrimaryButton(
                    label: 'Kaydet ve Başla',
                    loading: _saving,
                    onPressed: _saving ? null : _savePhone,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
