import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/signalr/signalr_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/bloc/auth_cubit.dart';

/// SignalR durum değişikliğini dinler ve 30 saniyelik polling'i yedek olarak
/// korur.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({
    super.key,
    this.enableLiveUpdates = true,
    this.onLogout,
  });

  final bool enableLiveUpdates;
  final Future<void> Function()? onLogout;

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  void Function()? _unsubscribe;
  Timer? _pollTimer;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.enableLiveUpdates) {
      _pulse.repeat(reverse: true);
      _unsubscribe = SignalRService.instance.on('BarberStatusChanged', (args) {
        final payload = args?.firstOrNull;
        if (payload is Map) {
          context.read<AuthCubit>().applyBarberStatus(
            payload['status'] as String,
            payload['rejectionReason'] as String?,
          );
        }
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) context.read<AuthCubit>().refreshUser();
      });
    } else {
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _unsubscribe?.call();
    _pollTimer?.cancel();
    super.dispose();
  }

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
    final user = context.watch<AuthCubit>().state.user;
    final rejected = user?.barberStatus == 'Rejected';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  minHeight: constraints.maxHeight - (AppSpacing.xl * 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 0.94, end: 1.04).animate(
                        CurvedAnimation(
                          parent: _pulse,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: rejected
                              ? const Color(0xFFFDECEC)
                              : AppColors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          rejected ? Icons.error_outline : Icons.hourglass_top,
                          size: 52,
                          color: rejected ? AppColors.error : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      rejected
                          ? 'Başvurunuz reddedildi'
                          : 'Hesabınız onay bekliyor',
                      textAlign: TextAlign.center,
                      style: AppTypography.headline,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      rejected
                          ? (user?.rejectionReason ??
                                'Başvurunuz incelendikten sonra reddedildi.')
                          : 'Belgeleriniz inceleniyor. Onaylandığında anında haberdar olacaksınız.',
                      key: const Key('approval_status_message'),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (!rejected)
                      const LinearProgressIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.primaryContainer,
                        borderRadius: BorderRadius.all(
                          Radius.circular(AppRadius.sm),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('pending_logout_button'),
                        onPressed: _loggingOut ? null : _logout,
                        child: _loggingOut
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.25,
                                ),
                              )
                            : const Text('Çıkış yap'),
                      ),
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
