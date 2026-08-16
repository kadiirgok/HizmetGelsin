import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../barber/data/business_working_hours.dart';

class BarberWorkingHoursSection extends StatefulWidget {
  const BarberWorkingHoursSection({
    super.key,
    required this.workingDays,
    this.nowProvider = DateTime.now,
  });

  final List<BusinessWorkingDay> workingDays;
  final DateTime Function() nowProvider;

  @override
  State<BarberWorkingHoursSection> createState() =>
      _BarberWorkingHoursSectionState();
}

class _BarberWorkingHoursSectionState extends State<BarberWorkingHoursSection> {
  static const _dayNames = <String>[
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  bool _expanded = false;

  Map<int, BusinessWorkingDay> get _daysByNumber {
    final days = <int, BusinessWorkingDay>{};
    for (final day in widget.workingDays) {
      if (day.day >= DateTime.monday && day.day <= DateTime.sunday) {
        days.putIfAbsent(day.day, () => day);
      }
    }
    return days;
  }

  String _hoursFor(BusinessWorkingDay? day) {
    if (day == null) return 'Belirtilmemiş';
    if (day.closed) return 'Kapalı';
    if (day.open.trim().isEmpty || day.close.trim().isEmpty) {
      return 'Belirtilmemiş';
    }
    return '${day.open}–${day.close}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.workingDays.isEmpty) return const _EmptyWorkingHours();

    final todayNumber = widget.nowProvider().weekday;
    final daysByNumber = _daysByNumber;
    final today = daysByNumber[todayNumber];
    final todayStatus = today == null
        ? 'Belirtilmemiş'
        : today.closed
        ? 'Kapalı'
        : 'Açık';
    final todayHours = today != null && !today.closed ? _hoursFor(today) : null;

    return Column(
      key: const ValueKey('barber-working-hours-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Çalışma Saatleri',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        _TodaySummary(
          status: todayStatus,
          hours: todayHours,
          expanded: _expanded,
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    key: const ValueKey('weekly-working-hours'),
                    children: [
                      for (var dayNumber = 1; dayNumber <= 7; dayNumber++)
                        _WeeklyDayRow(
                          dayName: _dayNames[dayNumber - 1],
                          hours: _hoursFor(daysByNumber[dayNumber]),
                          isToday: dayNumber == todayNumber,
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({
    required this.status,
    required this.expanded,
    required this.onTap,
    this.hours,
  });

  final String status;
  final String? hours;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusText = 'Bugün $status';
    final semanticsHours = hours?.replaceFirst('–', ' ile ');
    final actionText = expanded
        ? 'Haftalık saatleri gizle'
        : 'Haftalık saatleri göster';
    return Semantics(
      button: true,
      expanded: expanded,
      label: [
        'Çalışma saatleri',
        statusText.toLowerCase(),
        if (semanticsHours != null) '$semanticsHours arası',
        actionText.toLowerCase(),
      ].join(', '),
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('working-hours-toggle'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            key: const ValueKey('working-hours-today'),
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.fieldFill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.schedule_rounded, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (hours != null)
                        Text(
                          hours!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        actionText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeeklyDayRow extends StatelessWidget {
  const _WeeklyDayRow({
    required this.dayName,
    required this.hours,
    required this.isToday,
  });

  final String dayName;
  final String hours;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$dayName${isToday ? ', bugün' : ''}, $hours',
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('working-hours-day-$dayName'),
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isToday
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  hours,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: hours == 'Kapalı' || hours == 'Belirtilmemiş'
                        ? AppTheme.textSecondary
                        : Colors.black,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWorkingHours extends StatelessWidget {
  const _EmptyWorkingHours();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Çalışma Saatleri',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Çalışma saatleri henüz paylaşılmamış.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
