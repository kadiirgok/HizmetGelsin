import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../bloc/auth_cubit.dart';
import '../widgets/auth_widgets.dart';

class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key, this.onContinue});

  final void Function(BuildContext context, String role)? onContinue;

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fadeLogo;
  late final Animation<double> _fadeTitle;
  late final Animation<double> _fadeCards;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeLogo = CurvedAnimation(
      parent: _anim,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _fadeTitle = CurvedAnimation(
      parent: _anim,
      curve: const Interval(0.15, 0.6, curve: Curves.easeOutCubic),
    );
    _fadeCards = CurvedAnimation(
      parent: _anim,
      curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1.0;
    } else if (!_anim.isAnimating && !_anim.isCompleted) {
      _anim.addListener(() => setState(() {}));
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _go(String role) {
    if (_navigating) return;
    _navigating = true;
    if (widget.onContinue != null) {
      widget.onContinue!(context, role);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _navigating = false;
      });
      return;
    }
    context.read<AuthCubit>().selectRole(role);
    context.push('/giris-sifre').then((_) {
      if (mounted) _navigating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Builder(
          builder: (context) {
            return Column(
              children: [
                const Spacer(flex: 2),
                // Logo
                Opacity(
                  opacity: _fadeLogo.value,
                  child: const AuthBrandHeader(showName: true, logoSize: 72),
                ),
                const SizedBox(height: 32),
                // Title
                Opacity(
                  opacity: _fadeTitle.value,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        Text(
                          'Nasıl devam etmek\nistersiniz?',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Hizmet almak veya işletmenizi büyütmek için\nsize uygun seçeneği belirleyin.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                // Cards
                Opacity(
                  opacity: _fadeCards.value,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        _RoleOption(
                          icon: Icons.person_outline_rounded,
                          title: 'Hizmet almak istiyorum',
                          subtitle:
                              'Yakınınızdaki işletmeleri keşfedin,\nrandevu alın, hizmete ulaşın.',
                          color: cs.primary,
                          onTap: () => _go('Musteri'),
                        ),
                        const SizedBox(height: 14),
                        _RoleOption(
                          icon: Icons.store_rounded,
                          title: 'Hizmet vermek istiyorum',
                          subtitle:
                              'İşletmenizi ekleyin, müşterilere\nulaşın, işinizi büyütün.',
                          color: const Color(0xFFE8734A),
                          onTap: () => _go('Berber'),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 3),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RoleOption extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_RoleOption> createState() => _RoleOptionState();
}

class _RoleOptionState extends State<_RoleOption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) => _press.reverse(),
      onTapCancel: () => _press.reverse(),
      onTap: () {
        _press.reverse();
        widget.onTap();
      },
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEEEEE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(14),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.color.withAlpha(25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, size: 26, color: widget.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: widget.color.withAlpha(150)),
            ],
          ),
        ),
      ),
    );
  }
}
