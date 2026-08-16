part of '../../screens/barber_panel_screen.dart';

class BusinessHomeTodaySummary extends StatelessWidget {
  const BusinessHomeTodaySummary({
    super.key,
    required this.appointmentCount,
    required this.completedCount,
    required this.revenue,
  });

  final int appointmentCount;
  final int completedCount;
  final double revenue;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: _TodaySummaryValue(
                icon: Icons.event_note_outlined,
                value: '$appointmentCount',
                label: 'Randevu',
              ),
            ),
            Container(width: 1, height: 46, color: AppTheme.fieldFill),
            Expanded(
              child: _TodaySummaryValue(
                icon: Icons.task_alt_rounded,
                value: '$completedCount',
                label: 'Tamamlanan',
              ),
            ),
            Container(width: 1, height: 46, color: AppTheme.fieldFill),
            Expanded(
              child: _TodaySummaryValue(
                icon: Icons.payments_outlined,
                value: '${revenue.toStringAsFixed(0)} TL',
                label: 'Kazanç',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySummaryValue extends StatelessWidget {
  const _TodaySummaryValue({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 19),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 17,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
        ),
      ],
    );
  }
}
