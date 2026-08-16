part of '../../screens/barber_panel_screen.dart';

class BusinessHomeFocus extends StatelessWidget {
  const BusinessHomeFocus({
    super.key,
    required this.pendingRequestCount,
    required this.profileScore,
    required this.serviceCount,
    required this.photoCount,
    required this.isOnline,
    required this.todayConfirmedJobCount,
    required this.onOpenAppointments,
    required this.onOpenProfile,
    required this.onOpenProfileSettings,
    required this.onOpenServices,
    required this.onToggleOnline,
  });

  final int pendingRequestCount;
  final int profileScore;
  final int serviceCount;
  final int photoCount;
  final bool isOnline;
  final int todayConfirmedJobCount;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenProfileSettings;
  final VoidCallback onOpenServices;
  final Future<void> Function(bool value) onToggleOnline;

  @override
  Widget build(BuildContext context) {
    final actions = <_FocusAction>[
      if (!isOnline)
        _FocusAction(
          icon: Icons.wifi_off_rounded,
          title: 'İşletmeni çevrimiçi yap',
          description: 'Yeni müşteriler sizi görebilsin',
          onTap: () {
            onToggleOnline(true);
          },
        ),
      if (pendingRequestCount > 0)
        _FocusAction(
          icon: Icons.inbox_rounded,
          title: 'Yeni talepleri incele',
          description: '$pendingRequestCount müşteri talebi yanıt bekliyor',
          onTap: onOpenAppointments,
        ),
      if (profileScore < 100)
        _FocusAction(
          icon: Icons.storefront_outlined,
          title: 'Vitrinini tamamla',
          description: 'Profiliniz %$profileScore tamamlandı',
          onTap: onOpenProfileSettings,
        ),
      if (serviceCount == 0)
        _FocusAction(
          icon: Icons.add_business_outlined,
          title: 'İlk hizmetini ekle',
          description: 'Müşterilere sunduğunuz hizmetleri gösterin',
          onTap: onOpenServices,
        ),
      if (photoCount < 3)
        _FocusAction(
          icon: Icons.add_photo_alternate_outlined,
          title: 'Vitrinine fotoğraf ekle',
          description: 'En az 3 fotoğraf güveni artırır',
          onTap: onOpenProfile,
        ),
      if (todayConfirmedJobCount > 0)
        _FocusAction(
          icon: Icons.event_available_outlined,
          title: 'Yaklaşan randevularını kontrol et',
          description: 'Bugün $todayConfirmedJobCount işiniz var',
          onTap: onOpenAppointments,
        ),
    ];

    return _BusinessFocusCard(actions: actions.take(3).toList());
  }
}

class _FocusAction {
  const _FocusAction({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
}

class _BusinessFocusCard extends StatelessWidget {
  const _BusinessFocusCard({required this.actions});

  final List<_FocusAction> actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleActions = actions.isEmpty
        ? const <_FocusAction>[
            _FocusAction(
              icon: Icons.check_circle_outline_rounded,
              title: 'Bugün her şey yolunda',
              description:
                  'Yeni talepler ve randevular geldiğinde burada görünecek.',
            ),
          ]
        : actions;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: Container(
        key: ValueKey(visibleActions.map((action) => action.title).join('|')),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFECECEF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bugün odaklan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.25,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'İşinizi büyütmek için hızlı adımlar',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            for (var index = 0; index < visibleActions.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
              _BusinessFocusRow(action: visibleActions[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _BusinessFocusRow extends StatelessWidget {
  const _BusinessFocusRow({required this.action});

  final _FocusAction action;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(action.icon, color: const Color(0xFF111111), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (action.onTap != null) ...[
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Icon(
                Icons.chevron_right_rounded,
                color: Colors.black.withValues(alpha: 0.34),
                size: 22,
              ),
            ),
          ],
        ],
      ),
    );

    if (action.onTap == null) {
      return Semantics(
        label: '${action.title}. ${action.description}',
        child: content,
      );
    }

    return Semantics(
      button: true,
      label: '${action.title}. ${action.description}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: action.onTap, child: content),
      ),
    );
  }
}
