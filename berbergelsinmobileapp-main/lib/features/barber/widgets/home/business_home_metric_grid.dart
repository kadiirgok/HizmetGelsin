part of '../../screens/barber_panel_screen.dart';

class BusinessHomeMetricData {
  const BusinessHomeMetricData({
    required this.icon,
    required this.value,
    required this.title,
    required this.helper,
    required this.semanticLabel,
  });

  final IconData icon;
  final String value;
  final String title;
  final String helper;
  final String semanticLabel;
}

class BusinessHomeMetricGrid extends StatelessWidget {
  const BusinessHomeMetricGrid({super.key, required this.metrics});

  final List<BusinessHomeMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 360 ? 10.0 : 12.0;
        final firstRow = metrics.take(2).toList();
        final secondRow = metrics.skip(2).take(2).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BusinessHomeMetricRow(metrics: firstRow, gap: gap),
            if (secondRow.isNotEmpty) ...[
              SizedBox(height: gap),
              _BusinessHomeMetricRow(metrics: secondRow, gap: gap),
            ],
          ],
        );
      },
    );
  }
}

class _BusinessHomeMetricRow extends StatelessWidget {
  const _BusinessHomeMetricRow({required this.metrics, required this.gap});

  final List<BusinessHomeMetricData> metrics;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < metrics.length; index++) ...[
          if (index > 0) SizedBox(width: gap),
          Expanded(child: _BusinessHomeMetricCard(metrics[index])),
        ],
        if (metrics.length == 1) ...[SizedBox(width: gap), const Spacer()],
      ],
    );
  }
}

class _BusinessHomeMetricCard extends StatelessWidget {
  const _BusinessHomeMetricCard(this.metric);

  final BusinessHomeMetricData metric;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: metric.semanticLabel,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFECECEF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 145;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: compact ? 38 : 40,
                  height: compact ? 38 : 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F3F5),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    metric.icon,
                    color: const Color(0xFF111111),
                    size: compact ? 19 : 20,
                  ),
                ),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    metric.value,
                    maxLines: 1,
                    style: TextStyle(
                      color: const Color(0xFF111111),
                      fontSize: compact ? 27 : 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  metric.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF111111),
                    fontSize: compact ? 13.5 : 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  metric.helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: compact ? 12 : 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
