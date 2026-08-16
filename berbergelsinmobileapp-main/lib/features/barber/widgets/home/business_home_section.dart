part of '../../screens/barber_panel_screen.dart';

class BusinessHomeSection extends StatelessWidget {
  const BusinessHomeSection({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );

    if (child == null) return titleRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [titleRow, const SizedBox(height: 12), child!],
    );
  }
}
