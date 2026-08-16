import 'package:berbergelsin/features/barber/data/barber_customer_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BarberCustomerModel.fromJson', () {
    test('dolu customer JSON parse eder', () {
      final model = BarberCustomerModel.fromJson({
        'customerId': 'customer-1',
        'displayName': 'Ayşe Yılmaz',
        'firstVisit': '2026-07-01T10:00:00Z',
        'lastVisit': '2026-07-10T14:30:00Z',
        'completedJobCount': 3,
        'totalSpent': 1200.5,
        'averageTicket': 400.16,
        'preferredServices': ['Tesisat', 'Bakım'],
        'recentJobs': [
          {
            'requestId': 'request-1',
            'visitDate': '2026-07-10T14:30:00Z',
            'totalPrice': 450.75,
            'services': ['Tesisat'],
          },
        ],
      });

      expect(model.customerId, 'customer-1');
      expect(model.displayName, 'Ayşe Yılmaz');
      expect(model.completedJobCount, 3);
      expect(model.totalSpent, 1200.5);
      expect(model.averageTicket, 400.16);
      expect(model.preferredServices, ['Tesisat', 'Bakım']);
      expect(model.recentJobs.single.requestId, 'request-1');
      expect(model.recentJobs.single.totalPrice, 450.75);
    });

    test('decimal değer int gelirse güvenli parse eder', () {
      final model = BarberCustomerModel.fromJson({
        'customerId': 'customer-1',
        'displayName': 'Müşteri',
        'firstVisit': '2026-07-01T10:00:00Z',
        'lastVisit': '2026-07-10T14:30:00Z',
        'completedJobCount': 2,
        'totalSpent': 1200,
        'averageTicket': 600,
        'preferredServices': const [],
        'recentJobs': [
          {
            'requestId': 'request-1',
            'visitDate': '2026-07-10T14:30:00Z',
            'totalPrice': 450,
            'services': const [],
          },
        ],
      });

      expect(model.totalSpent, 1200.0);
      expect(model.averageTicket, 600.0);
      expect(model.recentJobs.single.totalPrice, 450.0);
    });

    test('null listeler boş liste olur', () {
      final model = BarberCustomerModel.fromJson({
        'customerId': 'customer-1',
        'displayName': 'Müşteri',
        'firstVisit': '2026-07-01T10:00:00Z',
        'lastVisit': '2026-07-10T14:30:00Z',
        'completedJobCount': null,
        'totalSpent': null,
        'averageTicket': null,
        'preferredServices': null,
        'recentJobs': null,
      });

      expect(model.completedJobCount, 0);
      expect(model.totalSpent, 0);
      expect(model.averageTicket, 0);
      expect(model.preferredServices, isEmpty);
      expect(model.recentJobs, isEmpty);
    });

    test('boş displayName Müşteri fallback kullanır', () {
      final model = BarberCustomerModel.fromJson({
        'customerId': 'customer-1',
        'displayName': '   ',
        'firstVisit': '2026-07-01T10:00:00Z',
        'lastVisit': '2026-07-10T14:30:00Z',
        'completedJobCount': 1,
        'totalSpent': 100,
        'averageTicket': 100,
        'preferredServices': const [],
        'recentJobs': const [],
      });

      expect(model.displayName, 'Müşteri');
    });

    test('service listesinde boş değerleri filtreler', () {
      final model = BarberCustomerModel.fromJson({
        'customerId': 'customer-1',
        'displayName': 'Müşteri',
        'firstVisit': '2026-07-01T10:00:00Z',
        'lastVisit': '2026-07-10T14:30:00Z',
        'completedJobCount': 1,
        'totalSpent': 100,
        'averageTicket': 100,
        'preferredServices': ['Tesisat', '', '  ', 'Bakım'],
        'recentJobs': [
          {
            'requestId': 'request-1',
            'visitDate': '2026-07-10T14:30:00Z',
            'totalPrice': 100,
            'services': ['Tesisat', '', '  '],
          },
        ],
      });

      expect(model.preferredServices, ['Tesisat', 'Bakım']);
      expect(model.recentJobs.single.services, ['Tesisat']);
    });
  });
}
