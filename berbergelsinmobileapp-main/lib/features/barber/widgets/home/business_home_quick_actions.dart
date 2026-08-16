part of '../../screens/barber_panel_screen.dart';

class BusinessHomeQuickActions extends StatelessWidget {
  const BusinessHomeQuickActions({
    super.key,
    required this.onOpenServices,
    required this.onOpenProfile,
    required this.onOpenProfileSettings,
    required this.onOpenAppointments,
    this.onOpenCustomers,
    this.onOpenPreview,
  });

  final VoidCallback onOpenServices;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenProfileSettings;
  final VoidCallback onOpenAppointments;
  final VoidCallback? onOpenCustomers;
  final VoidCallback? onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickActionItem>[
      _QuickActionItem(
        title: 'Hizmetlerim',
        subtitle: 'Hizmet ekle veya düzenle',
        icon: Icons.design_services_outlined,
        onTap: onOpenServices,
      ),
      _QuickActionItem(
        title: 'Fotoğraf ekle',
        subtitle: 'Vitrinini güncelle',
        icon: Icons.add_photo_alternate_outlined,
        onTap: onOpenProfile,
      ),
      _QuickActionItem(
        title: 'Profil ayarları',
        subtitle: 'İşletme bilgilerini düzenle',
        icon: Icons.tune_rounded,
        onTap: onOpenProfileSettings,
      ),
      _QuickActionItem(
        title: 'Randevular',
        subtitle: 'İşlerini yönet',
        icon: Icons.calendar_month_outlined,
        onTap: onOpenAppointments,
      ),
      if (onOpenCustomers != null)
        _QuickActionItem(
          title: 'Müşteriler',
          subtitle: 'Müşteri listenizi görüntüleyin',
          icon: Icons.people_outline_rounded,
          onTap: onOpenCustomers!,
        ),
      if (onOpenPreview != null)
        _QuickActionItem(
          title: 'Vitrin önizleme',
          subtitle: 'Müşterilerin gördüğünü incele',
          icon: Icons.visibility_outlined,
          onTap: onOpenPreview!,
        ),
    ].take(6).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn = constraints.maxWidth < 320;
        final gap = constraints.maxWidth < 360 ? 10.0 : 12.0;
        final width = singleColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: _QuickActionCard(action: action),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActionItem {
  const _QuickActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});

  final _QuickActionItem action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${action.title}. ${action.subtitle}.',
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 126),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFECECEF)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F3F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        action.icon,
                        color: const Color(0xFF111111),
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.black.withValues(alpha: 0.34),
                        size: 21,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  action.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    height: 1.14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  action.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
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
