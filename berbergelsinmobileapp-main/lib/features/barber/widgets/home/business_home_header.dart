part of '../../screens/barber_panel_screen.dart';

class BusinessHomeHeader extends StatelessWidget {
  const BusinessHomeHeader({super.key, required this.onRefresh});

  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ana Sayfa',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: compact ? 28 : 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.9,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'İşletmenizi bugün tek bakışta yönetin',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: compact ? 13 : 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Yenile',
              child: Material(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                elevation: 2,
                shadowColor: Colors.black.withValues(alpha: 0.12),
                child: InkWell(
                  onTap: () {
                    onRefresh();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFECECEF)),
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
