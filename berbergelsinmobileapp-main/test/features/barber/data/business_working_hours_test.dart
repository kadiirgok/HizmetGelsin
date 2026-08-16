import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/features/barber/data/business_working_hours.dart';

void main() {
  group('BusinessWorkingDay JSON Parsing and Serialization', () {
    test('should parse open day from JSON correctly', () {
      final json = {
        'day': 1,
        'open': '09:00',
        'close': '20:00',
        'closed': false,
      };
      final day = BusinessWorkingDay.fromJson(json);

      expect(day.day, 1);
      expect(day.open, '09:00');
      expect(day.close, '20:00');
      expect(day.closed, false);
      expect(day.dayName, 'Pazartesi');
      expect(day.openTimeOfDay, const TimeOfDay(hour: 9, minute: 0));
      expect(day.closeTimeOfDay, const TimeOfDay(hour: 20, minute: 0));
    });

    test('should parse closed day from JSON correctly', () {
      final json = {
        'day': 7,
        'open': '10:00',
        'close': '18:00',
        'closed': true,
      };
      final day = BusinessWorkingDay.fromJson(json);

      expect(day.day, 7);
      expect(day.open, '10:00');
      expect(day.close, '18:00');
      expect(day.closed, true);
      expect(day.dayName, 'Pazar');
    });

    test('should serialize to JSON correctly', () {
      const day = BusinessWorkingDay(
        day: 2,
        open: '08:30',
        close: '19:30',
        closed: false,
      );
      final json = day.toJson();

      expect(json['day'], 2);
      expect(json['open'], '08:30');
      expect(json['close'], '19:30');
      expect(json['closed'], false);
    });

    test('should handle broken/null hours safely without crashing', () {
      final json = {
        'day': null,
        'open': 'invalid',
        'close': null,
        'closed': null,
      };
      final day = BusinessWorkingDay.fromJson(json);

      expect(day.day, 1);
      expect(day.open, 'invalid');
      expect(day.close, '20:00'); // fallback
      expect(day.closed, false); // fallback

      // check that getters don't crash
      expect(day.openTimeOfDay, const TimeOfDay(hour: 9, minute: 0));
      expect(day.closeTimeOfDay, const TimeOfDay(hour: 20, minute: 0));
    });

    test('should handle missing workingHours cleanly (null behavior)', () {
      final defaultList = BusinessWorkingDay.defaultList();
      expect(defaultList.length, 7);
      expect(defaultList[0].day, 1);
      expect(defaultList[6].day, 7);
      expect(defaultList[0].closed, false);
    });
  });

  group('Working Hours Time Validation Helpers', () {
    test('isTimeBefore helper matches time comparisons correctly', () {
      const t9 = TimeOfDay(hour: 9, minute: 0);
      const t18 = TimeOfDay(hour: 18, minute: 0);
      const t18_30 = TimeOfDay(hour: 18, minute: 30);

      expect(isTimeBefore(t9, t18), isTrue);
      expect(isTimeBefore(t18, t9), isFalse);
      expect(isTimeBefore(t18, t18_30), isTrue);
      expect(isTimeBefore(t18_30, t18), isFalse);
      expect(isTimeBefore(t9, t9), isFalse);
    });

    test('formatTimeOfDay formats correctly with padding', () {
      expect(formatTimeOfDay(const TimeOfDay(hour: 9, minute: 5)), '09:05');
      expect(formatTimeOfDay(const TimeOfDay(hour: 13, minute: 45)), '13:45');
    });
  });
}
