import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../bloc/auth_cubit.dart';

class AccountBlockedScreen extends StatefulWidget {
  const AccountBlockedScreen({super.key, this.onLogout});

  final Future<void> Function()? onLogout;

  @override
  State<AccountBlockedScreen> createState() => _AccountBlockedScreenState();
}

class _AccountBlockedScreenState extends State<AccountBlockedScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      if (widget.onLogout != null) {
        await widget.onLogout!();
      } else {
        await context.read<AuthCubit>().logout();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Çıkış yapılamadı. Lütfen tekrar deneyin.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesap durumu')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text(
                    'Hesabınıza erişilemiyor',
                    style: AppTypography.headline,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Hesap durumunuz nedeniyle oturumunuz güvenli şekilde kapatıldı.',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('blocked_logout_button'),
                      onPressed: _loggingOut ? null : _logout,
                      child: _loggingOut
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.25,
                              ),
                            )
                          : const Text('Giriş ekranına dön'),
                    ),
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
