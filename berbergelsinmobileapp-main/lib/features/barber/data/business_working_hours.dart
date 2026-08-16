import 'package:flutter/material.dart';

class BusinessWorkingDay {
  final int day; // 1 = Pazartesi, ..., 7 = Pazar
  final String open; // "HH:mm"
  final String close; // "HH:mm"
  final bool closed;

  const BusinessWorkingDay({
    required this.day,
    required this.open,
    required this.close,
    required this.closed,
  });

  factory BusinessWorkingDay.fromJson(Map<String, dynamic> json) {
    // Robust parsing in case of unexpected format or null
    final dayVal = json['day'] ?? json['Day'];
    int parsedDay = 1;
    if (dayVal is num) {
      parsedDay = dayVal.toInt();
    } else if (dayVal is String) {
      parsedDay = int.tryParse(dayVal) ?? 1;
    }

    final openVal = (json['open'] ?? json['Open']) as String? ?? '09:00';
    final closeVal = (json['close'] ?? json['Close']) as String? ?? '20:00';
    final closedVal = (json['closed'] ?? json['Closed']) as bool? ?? false;

    return BusinessWorkingDay(
      day: parsedDay,
      open: openVal,
      close: closeVal,
      closed: closedVal,
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day,
    'open': open,
    'close': close,
    'closed': closed,
  };

  TimeOfDay get openTimeOfDay {
    try {
      final parts = open.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    return const TimeOfDay(hour: 9, minute: 0);
  }

  TimeOfDay get closeTimeOfDay {
    try {
      final parts = close.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    return const TimeOfDay(hour: 20, minute: 0);
  }

  String get dayName {
    switch (day) {
      case 1:
        return 'Pazartesi';
      case 2:
        return 'Salı';
      case 3:
        return 'Çarşamba';
      case 4:
        return 'Perşembe';
      case 5:
        return 'Cuma';
      case 6:
        return 'Cumartesi';
      case 7:
        return 'Pazar';
      default:
        return 'Bilinmeyen Gün';
    }
  }

  BusinessWorkingDay copyWith({
    int? day,
    String? open,
    String? close,
    bool? closed,
  }) {
    return BusinessWorkingDay(
      day: day ?? this.day,
      open: open ?? this.open,
      close: close ?? this.close,
      closed: closed ?? this.closed,
    );
  }

  // Generates default list of days for working hours
  static List<BusinessWorkingDay> defaultList() {
    return List.generate(7, (index) {
      final dayNum = index + 1;
      return BusinessWorkingDay(
        day: dayNum,
        open: '09:00',
        close: '20:00',
        closed: false,
      );
    });
  }
}

String formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

bool isTimeBefore(TimeOfDay a, TimeOfDay b) {
  if (a.hour < b.hour) return true;
  if (a.hour > b.hour) return false;
  return a.minute < b.minute;
}
