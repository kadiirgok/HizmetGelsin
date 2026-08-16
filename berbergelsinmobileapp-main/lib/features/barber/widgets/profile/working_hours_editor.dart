import 'package:flutter/material.dart';
import '../../data/business_working_hours.dart';
import '../../../../core/theme/app_theme.dart';

class WorkingHoursEditorScreen extends StatefulWidget {
  const WorkingHoursEditorScreen({
    super.key,
    required this.workingHours,
    required this.onSave,
  });

  final List<BusinessWorkingDay> workingHours;
  final Future<void> Function(List<BusinessWorkingDay> updatedHours) onSave;

  @override
  State<WorkingHoursEditorScreen> createState() =>
      _WorkingHoursEditorScreenState();
}

class _WorkingHoursEditorScreenState extends State<WorkingHoursEditorScreen> {
  late List<BusinessWorkingDay> _tempHours;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Initialize temporary list and ensure it contains all 7 days in order
    final Map<int, BusinessWorkingDay> map = {
      for (final day in widget.workingHours) day.day: day,
    };
    _tempHours = List.generate(7, (index) {
      final dayNum = index + 1;
      return map[dayNum] ??
          BusinessWorkingDay(
            day: dayNum,
            open: '09:00',
            close: '20:00',
            closed: true, // Default to closed if not provided
          );
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
      );
  }

  Future<void> _selectTime(
    BuildContext context,
    int index, {
    required bool isOpenTime,
  }) async {
    if (_busy) return;
    final day = _tempHours[index];
    final initialTime = isOpenTime ? day.openTimeOfDay : day.closeTimeOfDay;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (selectedTime != null) {
      final formatted = formatTimeOfDay(selectedTime);
      setState(() {
        if (isOpenTime) {
          _tempHours[index] = day.copyWith(open: formatted);
        } else {
          _tempHours[index] = day.copyWith(close: formatted);
        }
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;

    // Validation
    for (final day in _tempHours) {
      if (!day.closed) {
        final start = day.openTimeOfDay;
        final end = day.closeTimeOfDay;

        if (start.hour == end.hour && start.minute == end.minute) {
          _showError(
            '${day.dayName} günü için açılış ve kapanış saatleri aynı olamaz.',
          );
          return;
        }

        if (!isTimeBefore(start, end)) {
          _showError(
            '${day.dayName} günü için kapanış saati açılış saatinden önce olamaz.',
          );
          return;
        }
      }
    }

    setState(() => _busy = true);
    try {
      await widget.onSave(_tempHours);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Çalışma saatleri başarıyla güncellendi.'),
              backgroundColor: Colors.green,
            ),
          );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showError('Çalışma saatleri kaydedilemedi. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Çalışma Saatleri')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _tempHours.length,
                itemBuilder: (context, index) {
                  final day = _tempHours[index];
                  return Card(
                    key: ValueKey(day.day),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  day.dayName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Semantics(
                                label:
                                    '${day.dayName} ${day.closed ? 'kapalı' : 'açık'}',
                                child: Switch(
                                  value: !day.closed,
                                  activeThumbColor: AppTheme.primary,
                                  onChanged: _busy
                                      ? null
                                      : (val) {
                                          setState(() {
                                            _tempHours[index] = day.copyWith(
                                              closed: !val,
                                            );
                                          });
                                        },
                                ),
                              ),
                            ],
                          ),
                          if (!day.closed) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              alignment: WrapAlignment.start,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _buildTimeButton(
                                  context,
                                  label: 'Açılış',
                                  time: day.openTimeOfDay,
                                  onTap: () => _selectTime(
                                    context,
                                    index,
                                    isOpenTime: true,
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: AppTheme.textSecondary,
                                ),
                                _buildTimeButton(
                                  context,
                                  label: 'Kapanış',
                                  time: day.closeTimeOfDay,
                                  onTap: () => _selectTime(
                                    context,
                                    index,
                                    isOpenTime: false,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Semantics(
                  label: 'Çalışma saatlerini kaydet',
                  button: true,
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Değişiklikleri Kaydet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeButton(
    BuildContext context, {
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    final timeStr = formatTimeOfDay(time);
    return Semantics(
      label: '$label saati $timeStr',
      button: true,
      child: OutlinedButton(
        onPressed: _busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.access_time_filled_rounded,
              size: 16,
              color: AppTheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$label: $timeStr',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
