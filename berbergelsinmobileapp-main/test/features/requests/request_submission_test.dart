import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/core/api/api_client.dart';
import 'package:berbergelsin/features/barber/data/business_working_hours.dart';
import 'package:berbergelsin/features/requests/controllers/request_submission.dart';
import 'package:berbergelsin/features/requests/data/requests_repo.dart';

void main() {
  test('generated key is RFC 4122 UUID v4 shaped', () {
    expect(
      newRequestUuid(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('retry keeps key, form change rotates it, success closes it', () {
    var count = 0;
    final session = RequestSubmissionSession(
      keyFactory: () => 'key-${++count}',
    );
    expect(session.begin(), 'key-1');
    session.failed(RequestSubmissionState.networkError);
    expect(session.begin(), 'key-1');
    session.failed(RequestSubmissionState.validationError);
    session.formChanged();
    expect(session.begin(), 'key-2');
    session.succeeded();
    expect(session.activeKey, isNull);
    expect(session.state, RequestSubmissionState.success);
  });

  test('second begin during submitting cannot create a second key', () {
    var count = 0;
    final session = RequestSubmissionSession(
      keyFactory: () => 'key-${++count}',
    );
    expect(session.begin(), session.begin());
    expect(count, 1);
  });

  test(
    'transport sends idempotency header, removes duplicates and never sends price',
    () {
      final value = buildServiceRequestTransport(
        barberProfileId: 'b',
        serviceIds: ['s', 's'],
        requestedTime: DateTime.utc(2026, 7, 16, 10),
        lat: 41,
        lng: 29,
        addressNote: 'adres',
        idempotencyKey: 'uuid',
      );
      expect(value.headers, {'Idempotency-Key': 'uuid'});
      expect(value.body['serviceIds'], ['s']);
      expect(value.body.containsKey('price'), isFalse);
    },
  );

  test('shop request can omit address coordinates', () {
    final value = buildServiceRequestTransport(
      barberProfileId: 'b',
      serviceIds: ['s'],
      requestedTime: DateTime.utc(2026, 7, 16, 10),
      idempotencyKey: 'uuid',
    );
    expect(value.body.containsKey('lat'), isFalse);
    expect(value.body.containsKey('lng'), isFalse);
  });

  test('saved address sends addressId while manual address omits it', () {
    final saved = buildServiceRequestTransport(
      barberProfileId: 'b',
      serviceIds: ['s'],
      requestedTime: DateTime.utc(2026, 7, 16, 10),
      addressId: 'address-1',
      serviceLocationType: 'customerAddress',
      lat: 1,
      lng: 2,
      addressNote: 'backward-compatible snapshot',
      idempotencyKey: 'same-key',
    );
    expect(saved.body['addressId'], 'address-1');
    expect(saved.body['serviceLocationType'], 'customerAddress');
    expect(saved.body['addressNote'], 'backward-compatible snapshot');
    expect(saved.headers['Idempotency-Key'], 'same-key');

    final manual = buildServiceRequestTransport(
      barberProfileId: 'b',
      serviceIds: ['s'],
      requestedTime: DateTime.utc(2026, 7, 16, 10),
      serviceLocationType: 'customerAddress',
      lat: 41,
      lng: 29,
      addressNote: 'manual',
      idempotencyKey: 'manual-key',
    );
    expect(manual.body.containsKey('addressId'), isFalse);
  });

  test(
    'backend request errors map to safe states and do not expose raw text',
    () {
      final cases = {
        'request_time_conflict': RequestSubmissionState.timeConflict,
        'request_outside_service_area':
            RequestSubmissionState.outsideServiceArea,
        'request_business_unavailable':
            RequestSubmissionState.businessUnavailable,
        'request_service_unavailable':
            RequestSubmissionState.serviceUnavailable,
        'request_rate_limited': RequestSubmissionState.rateLimited,
        'request_idempotency_conflict': RequestSubmissionState.validationError,
      };
      for (final entry in cases.entries) {
        final mapped = mapRequestError(
          ApiException('raw sql secret', code: entry.key),
        );
        expect(mapped.state, entry.value);
        expect(mapped.message, isNot(contains('raw sql secret')));
      }
      expect(
        mapRequestError(ApiException('raw', kind: ApiErrorKind.network)).state,
        RequestSubmissionState.networkError,
      );
    },
  );

  test('request HTTP error matrix is safe and timeout preserves retry key', () {
    for (final status in [400, 403, 404, 409, 429, 500, 503]) {
      final mapped = mapRequestError(
        ApiException('raw backend message', statusCode: status),
      );
      expect(mapped.message, isNot(contains('raw backend message')));
    }
    var sequence = 0;
    final session = RequestSubmissionSession(
      keyFactory: () => 'k${++sequence}',
    );
    final first = session.begin();
    session.failed(
      mapRequestError(
        ApiException('timeout', kind: ApiErrorKind.timeout),
      ).state,
    );
    expect(session.begin(), first);
  });

  test('past, over 90 days and outside working hours are rejected', () {
    final now = DateTime.now();
    final allDays = List.generate(
      7,
      (i) => BusinessWorkingDay(
        day: i + 1,
        open: '09:00',
        close: '18:00',
        closed: false,
      ),
    );
    expect(
      requestTimeInsideWorkingHours(
        now.subtract(const Duration(minutes: 1)),
        allDays,
      ),
      isFalse,
    );
    expect(
      requestTimeInsideWorkingHours(now.add(const Duration(days: 91)), allDays),
      isFalse,
    );
    var valid = now.add(const Duration(days: 1));
    valid = DateTime(valid.year, valid.month, valid.day, 10);
    expect(requestTimeInsideWorkingHours(valid, allDays), isTrue);
    expect(
      requestTimeInsideWorkingHours(
        DateTime(valid.year, valid.month, valid.day, 20),
        allDays,
      ),
      isFalse,
    );
  });
}
