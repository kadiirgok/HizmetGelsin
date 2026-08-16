import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/widgets/auth_widgets.dart';
import '../data/onboarding_repo.dart';
import '../widgets/kvkk_sheet.dart';

typedef ClientOnboardingSubmit =
    Future<void> Function({
      required String firstName,
      required String lastName,
      required String email,
      required String phone,
    });

class ClientOnboardingScreen extends StatefulWidget {
  const ClientOnboardingScreen({super.key, this.submit, this.onCompleted});

  final ClientOnboardingSubmit? submit;
  final Future<void> Function()? onCompleted;

  @override
  State<ClientOnboardingScreen> createState() => _ClientOnboardingScreenState();
}

class _ClientOnboardingScreenState extends State<ClientOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _kvkkAccepted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthCubit>().state.user;
    if (user != null) {
      _firstName.text = user.firstName ?? '';
      _lastName.text = user.lastName ?? '';
      _email.text = user.email ?? '';
      _phone.text = formatTurkishMobile(user.phone);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.error : null,
        ),
      );
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_kvkkAccepted) {
      _showMessage(
        'Devam etmek için KVKK metnini kabul etmelisiniz.',
        error: true,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final submit = widget.submit ?? OnboardingRepo.instance.submitClient;
      await submit(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim(),
        phone: normalizeTurkishMobile(_phone.text),
      );
      if (!mounted) return;
      if (widget.onCompleted != null) {
        await widget.onCompleted!();
      } else if (widget.submit == null) {
        await context.read<AuthCubit>().refreshUser();
      }
    } on ApiException catch (e) {
      _showMessage(e.message, error: true);
    } catch (_) {
      _showMessage(
        'Kaydınız tamamlanamadı. Lütfen tekrar deneyin.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabını tamamla')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Sizi tanıyalım', style: AppTypography.headline),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Randevularınızda kullanılacak temel bilgileri tamamlayın.',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextFormField(
                      key: const Key('client_first_name'),
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Ad'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Ad zorunludur.'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const Key('client_last_name'),
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Soyad'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Soyad zorunludur.'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const Key('client_email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-posta'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'E-posta zorunludur.';
                        if (!RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(email)) {
                          return 'Geçerli bir e-posta girin.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Semantics(
                      label: 'Doğrulanmış telefon numarası',
                      readOnly: true,
                      child: TextFormField(
                        controller: _phone,
                        readOnly: true,
                        enableInteractiveSelection: false,
                        decoration: const InputDecoration(
                          labelText: 'Doğrulanmış telefon',
                          prefixText: '+90 ',
                          fillColor: AppColors.primaryContainer,
                          suffixIcon: Icon(
                            Icons.verified,
                            color: AppColors.success,
                            semanticLabel: 'Doğrulandı',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Semantics(
                      container: true,
                      label: 'KVKK ve kullanım koşulları onayı',
                      child: CheckboxListTile(
                        key: const Key('client_kvkk_checkbox'),
                        value: _kvkkAccepted,
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _kvkkAccepted = value ?? false,
                              ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Kullanım Koşullarını ve KVKK Aydınlatma Metnini okudum, kabul ediyorum.',
                        ),
                        subtitle: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => showKvkkSheet(context),
                            child: const Text('Metni görüntüle'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    LoadingPrimaryButton(
                      label: 'Kaydı Tamamla',
                      loading: _busy,
                      onPressed: _busy ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
