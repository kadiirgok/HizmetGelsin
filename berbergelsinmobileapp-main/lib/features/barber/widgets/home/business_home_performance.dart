part of '../../screens/barber_panel_screen.dart';

class BusinessHomePerformance extends StatelessWidget {
  const BusinessHomePerformance({
    super.key,
    required this.weekRevenue,
    required this.totalRevenue,
    required this.averageResponseMinutes,
    required this.conversionRate,
    required this.completedThisWeek,
    required this.uniqueCustomerCount,
  });

  final double weekRevenue;
  final double totalRevenue;
  final int averageResponseMinutes;
  final int conversionRate;
  final int completedThisWeek;
  final int uniqueCustomerCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 340;
        final gap = compact ? 10.0 : 12.0;

        return Container(
          padding: EdgeInsets.all(compact ? 16 : 18),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PerformanceRevenueItem(
                      label: 'Bu hafta',
                      value: _currency(weekRevenue),
                      semantics: 'Bu haftaki gelir: ${_currency(weekRevenue)}',
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 14,
                    ),
                    child: Container(
                      width: 1,
                      height: 58,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  Expanded(
                    child: _PerformanceRevenueItem(
                      label: 'Toplam gelir',
                      value: _currency(totalRevenue),
                      semantics: 'Toplam gelir: ${_currency(totalRevenue)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _PerformanceIndicator(
                      icon: Icons.schedule_rounded,
                      value: averageResponseMinutes <= 0
                          ? '—'
                          : '$averageResponseMinutes dk',
                      label: 'Yanıt süresi',
                      semantics: averageResponseMinutes <= 0
                          ? 'Ortalama yanıt süresi: Henüz ölçülmedi'
                          : 'Ortalama yanıt süresi: $averageResponseMinutes dakika',
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: _PerformanceIndicator(
                      icon: Icons.trending_up_rounded,
                      value: '%$conversionRate',
                      label: compact ? 'Dönüşüm' : 'Dönüşüm oranı',
                      semantics: 'Dönüşüm oranı: yüzde $conversionRate',
                    ),
                  ),
                ],
              ),
              SizedBox(height: gap),
              Row(
                children: [
                  Expanded(
                    child: _PerformanceIndicator(
                      icon: Icons.task_alt_rounded,
                      value: '$completedThisWeek',
                      label: compact ? 'Tamamlanan' : 'Bu hafta tamamlanan',
                      semantics: 'Bu hafta tamamlanan iş: $completedThisWeek',
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: _PerformanceIndicator(
                      icon: Icons.people_outline_rounded,
                      value: '$uniqueCustomerCount',
                      label: 'Toplam müşteri',
                      semantics: 'Toplam müşteri: $uniqueCustomerCount',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _currency(double value) {
    final hasFraction = (value - value.truncateToDouble()).abs() > 0.001;
    final fixed = value.abs().toStringAsFixed(hasFraction ? 2 : 0);
    final pieces = fixed.split('.');
    final whole = pieces.first;
    final buffer = StringBuffer();
    for (var index = 0; index < whole.length; index++) {
      final remaining = whole.length - index;
      buffer.write(whole[index]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
    }
    final sign = value < 0 ? '-' : '';
    final fraction = hasFraction && pieces.length > 1 ? ',${pieces.last}' : '';
    return '$sign₺$buffer$fraction';
  }
}

class _PerformanceRevenueItem extends StatelessWidget {
  const _PerformanceRevenueItem({
    required this.label,
    required this.value,
    required this.semantics,
  });

  final String label;
  final String value;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceIndicator extends StatelessWidget {
  const _PerformanceIndicator({
    required this.icon,
    required this.value,
    required this.label,
    required this.semantics,
  });

  final IconData icon;
  final String value;
  final String label;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      child: Container(
        constraints: const BoxConstraints(minHeight: 102),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.075),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                color: Colors.white.withValues(alpha: 0.72),
                size: 21,
              ),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
