import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

class ServiceRequestModel {
  ServiceRequestModel({
    required this.id,
    required this.barberProfileId,
    this.barberBusinessName,
    this.clientName,
    this.clientPhone,
    this.barberPhone,
    required this.status,
    required this.requestedTime,
    required this.lat,
    required this.lng,
    this.addressNote,
    required this.totalPrice,
    required this.items,
    required this.createdAt,
    this.onTheWayAt,
    this.startedAt,
    this.completedAt,
    this.barberLat,
    this.barberLng,
    required this.canRate,
    this.myScore,
    this.addressId,
    this.addressSnapshot,
    this.serviceLocationType,
    this.updatedAt,
    this.concurrencyToken,
    this.respondedAt,
    this.cancelledAt,
  });

  final String id;
  final String barberProfileId;
  final String? barberBusinessName;
  final String? clientName;
  final String? clientPhone;
  final String? barberPhone;

  /// Pending | Accepted | Rejected | Completed | Cancelled | OnTheWay | Started | ReschedulePending
  String status;
  final DateTime requestedTime;
  final double? lat;
  final double? lng;
  final String? addressNote;
  final double totalPrice;
  final List<({String serviceName, double price})> items;
  final DateTime createdAt;
  final DateTime? onTheWayAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? respondedAt;
  final DateTime? cancelledAt;

  /// Yoldayken hizmet verenin bilinen son konumu (takip başlangıcı için)
  final double? barberLat;
  final double? barberLng;
  final bool canRate;
  final int? myScore;
  final String? addressId,
      addressSnapshot,
      serviceLocationType,
      concurrencyToken;
  final DateTime? updatedAt;

  bool get isActive =>
      status == 'Pending' ||
      status == 'Accepted' ||
      status == 'OnTheWay' ||
      status == 'Started' ||
      status == 'ReschedulePending';

  factory ServiceRequestModel.fromJson(Map<String, dynamic> json) =>
      ServiceRequestModel(
        id: json['id'] as String,
        barberProfileId: json['barberProfileId'] as String,
        barberBusinessName: json['barberBusinessName'] as String?,
        clientName: json['clientName'] as String?,
        clientPhone: json['clientPhone'] as String?,
        barberPhone: json['barberPhone'] as String?,
        status: json['status'] as String,
        requestedTime: DateTime.parse(
          json['requestedTime'] as String,
        ).toLocal(),
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        addressNote: json['addressNote'] as String?,
        totalPrice: (json['totalPrice'] as num).toDouble(),
        items: (json['items'] as List)
            .map(
              (i) => (
                serviceName: i['serviceName'] as String,
                price: (i['price'] as num).toDouble(),
              ),
            )
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        onTheWayAt: json['onTheWayAt'] == null
            ? null
            : DateTime.parse(json['onTheWayAt'] as String).toLocal(),
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.parse(json['startedAt'] as String).toLocal(),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String).toLocal(),
        barberLat: (json['barberLat'] as num?)?.toDouble(),
        barberLng: (json['barberLng'] as num?)?.toDouble(),
        canRate: json['canRate'] as bool? ?? false,
        myScore: json['myScore'] as int?,
        addressId: json['addressId'] as String?,
        addressSnapshot: json['addressSnapshot'] as String?,
        serviceLocationType: json['serviceLocationType'] as String?,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String).toLocal(),
        concurrencyToken: json['concurrencyToken'] as String?,
        respondedAt: json['respondedAt'] == null
            ? null
            : DateTime.parse(json['respondedAt'] as String).toLocal(),
        cancelledAt: json['cancelledAt'] == null
            ? null
            : DateTime.parse(json['cancelledAt'] as String).toLocal(),
      );
}

class RequestPage {
  const RequestPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
  });
  final List<ServiceRequestModel> items;
  final int page, pageSize, totalCount, totalPages;

  factory RequestPage.fromJson(Map<String, dynamic> json) => RequestPage(
        items: (json['items'] as List? ?? [])
            .whereType<Map>()
            .map(
                (e) => ServiceRequestModel.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        page: json['page'] as int? ?? 1,
        pageSize: json['pageSize'] as int? ?? 50,
        totalCount: json['totalCount'] as int? ?? 0,
        totalPages: json['totalPages'] as int? ?? 0,
      );
}

class RequestTimelineEntry {
  const RequestTimelineEntry({
    required this.id,
    required this.fromStatus,
    required this.toStatus,
    required this.changedByRole,
    this.reasonCode,
    this.reasonText,
    required this.createdAt,
  });
  final String id, fromStatus, toStatus, changedByRole;
  final String? reasonCode, reasonText;
  final DateTime createdAt;
  factory RequestTimelineEntry.fromJson(Map<String, dynamic> json) =>
      RequestTimelineEntry(
        id: json['id'] as String,
        fromStatus: json['fromStatus'] as String,
        toStatus: json['toStatus'] as String,
        changedByRole: json['changedByRole'] as String,
        reasonCode: json['reasonCode'] as String?,
        reasonText: json['reasonText'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}

List<RequestTimelineEntry> mapRequestTimeline(List<dynamic> data) {
  final unique = <String, RequestTimelineEntry>{
    for (final row in data)
      (row as Map<String, dynamic>)['id'] as String:
          RequestTimelineEntry.fromJson(row),
  };
  return unique.values.toList()..sort((a, b) {
    final byDate = a.createdAt.compareTo(b.createdAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  });
}

abstract interface class RequestTrackingRepository {
  Future<RequestPage> mine({int page = 1, int pageSize = 50});
  Future<ServiceRequestModel> detail(String id);
  Future<List<RequestTimelineEntry>> timeline(String id);
  Future<void> cancelRequest(
    String id, {
    required String reasonCode,
    String? reasonText,
    required String idempotencyKey,
  });
  Future<void> reschedule(
    String id,
    DateTime requestedStartAt, {
    String? reason,
    required String idempotencyKey,
  });
  Future<void> resolveReschedule(
    String id,
    bool accept, {
    required String idempotencyKey,
  });
}

({String path, Map<String, dynamic>? body, Map<String, String> headers})
buildRequestLifecycleTransport(
  String id,
  String action, {
  String? reasonCode,
  String? reasonText,
  DateTime? requestedStartAt,
  required String idempotencyKey,
}) => (
  path: '/api/requests/$id/$action',
  body: action == 'cancel'
      ? {'reasonCode': reasonCode, 'reasonText': reasonText}
      : action == 'reschedule'
      ? {
          'requestedStartAt': requestedStartAt!.toUtc().toIso8601String(),
          'reason': reasonText,
        }
      : null,
  headers: {'Idempotency-Key': idempotencyKey},
);

class PriceOfferModel {
  PriceOfferModel({
    required this.id,
    required this.barberProfileId,
    this.barberBusinessName,
    this.clientName,
    required this.proposedPrice,
    this.counterPrice,
    required this.status,
    required this.requestedTime,
    this.note,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedPrice,
  });

  final String id;
  final String barberProfileId;
  final String? barberBusinessName;
  final String? clientName;
  final double proposedPrice;
  double? counterPrice;
  String status;
  final DateTime requestedTime;
  final String? note;
  final DateTime createdAt;
  final DateTime expiresAt;
  final double? acceptedPrice;

  bool get isExpired =>
      status == 'Expired' || DateTime.now().isAfter(expiresAt);

  factory PriceOfferModel.fromJson(Map<String, dynamic> json) =>
      PriceOfferModel(
        id: json['id'] as String,
        barberProfileId: json['barberProfileId'] as String,
        barberBusinessName: json['barberBusinessName'] as String?,
        clientName: json['clientName'] as String?,
        proposedPrice: (json['proposedPrice'] as num).toDouble(),
        counterPrice: (json['counterPrice'] as num?)?.toDouble(),
        status: json['status'] as String,
        requestedTime: DateTime.parse(
          json['requestedTime'] as String,
        ).toLocal(),
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
        acceptedPrice: (json['acceptedPrice'] as num?)?.toDouble(),
      );
}

abstract interface class ServiceRequestCreator {
  Future<ServiceRequestModel> create({
    required String barberProfileId,
    required List<String> serviceIds,
    required DateTime requestedTime,
    double? lat,
    double? lng,
    String? addressNote,
    String? addressId,
    String? serviceLocationType,
    double? proposedPrice,
    required String idempotencyKey,
  });
}

({Map<String, dynamic> body, Map<String, String> headers})
buildServiceRequestTransport({
  required String barberProfileId,
  required List<String> serviceIds,
  required DateTime requestedTime,
  double? lat,
  double? lng,
  String? addressNote,
  String? addressId,
  String? serviceLocationType,
  double? proposedPrice,
  required String idempotencyKey,
}) => (
  body: {
    'barberProfileId': barberProfileId,
    'serviceIds': serviceIds.toSet().toList(growable: false),
    'requestedTime': requestedTime.toUtc().toIso8601String(),
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    'addressNote': addressNote,
    if (addressId != null) 'addressId': addressId,
    if (serviceLocationType != null) 'serviceLocationType': serviceLocationType,
    if (proposedPrice != null) 'proposedPrice': proposedPrice,
  },
  headers: {'Idempotency-Key': idempotencyKey},
);

class RequestsRepo implements ServiceRequestCreator, RequestTrackingRepository {
  RequestsRepo._();
  static final RequestsRepo instance = RequestsRepo._();

  final _api = ApiClient.instance;

  @override
  Future<ServiceRequestModel> create({
    required String barberProfileId,
    required List<String> serviceIds,
    required DateTime requestedTime,
    double? lat,
    double? lng,
    String? addressNote,
    String? addressId,
    String? serviceLocationType,
    double? proposedPrice,
    required String idempotencyKey,
  }) async {
    final transport = buildServiceRequestTransport(
      barberProfileId: barberProfileId,
      serviceIds: serviceIds,
      requestedTime: requestedTime,
      lat: lat,
      lng: lng,
      addressNote: addressNote,
      addressId: addressId,
      serviceLocationType: serviceLocationType,
      proposedPrice: proposedPrice,
      idempotencyKey: idempotencyKey,
    );
    return ServiceRequestModel.fromJson(
      await _api.post<Map<String, dynamic>>(
        '/api/requests',
        data: transport.body,
        headers: transport.headers,
      ),
    );
  }

  @override
  Future<RequestPage> mine({int page = 1, int pageSize = 50}) async =>
      RequestPage.fromJson(await _api.get<Map<String, dynamic>>(
        '/api/requests/mine?page=$page&pageSize=$pageSize',
      ));

  @override
  Future<ServiceRequestModel> detail(String id) async {
    return ServiceRequestModel.fromJson(
      await _api.get<Map<String, dynamic>>('/api/requests/$id'),
    );
  }

  @override
  Future<List<RequestTimelineEntry>> timeline(String id) async {
    final data = await _api.get<List<dynamic>>('/api/requests/$id/timeline');
    return mapRequestTimeline(data);
  }

  @override
  Future<void> cancelRequest(
    String id, {
    required String reasonCode,
    String? reasonText,
    required String idempotencyKey,
  }) async {
    final t = buildRequestLifecycleTransport(
      id,
      'cancel',
      reasonCode: reasonCode,
      reasonText: reasonText,
      idempotencyKey: idempotencyKey,
    );
    await _api.post(t.path, data: t.body, headers: t.headers);
  }

  @override
  Future<void> reschedule(
    String id,
    DateTime requestedStartAt, {
    String? reason,
    required String idempotencyKey,
  }) async {
    final t = buildRequestLifecycleTransport(
      id,
      'reschedule',
      requestedStartAt: requestedStartAt,
      reasonText: reason,
      idempotencyKey: idempotencyKey,
    );
    await _api.post(t.path, data: t.body, headers: t.headers);
  }

  @override
  Future<void> resolveReschedule(
    String id,
    bool accept, {
    required String idempotencyKey,
  }) async {
    final t = buildRequestLifecycleTransport(
      id,
      accept ? 'reschedule/accept' : 'reschedule/reject',
      idempotencyKey: idempotencyKey,
    );
    await _api.post(t.path, headers: t.headers);
  }

  Future<void> accept(String id, {required String idempotencyKey}) =>
      _api.post('/api/requests/$id/accept',
          headers: {'Idempotency-Key': idempotencyKey});
  Future<void> reject(String id, {required String idempotencyKey}) =>
      _api.post('/api/requests/$id/reject',
          headers: {'Idempotency-Key': idempotencyKey});
  Future<void> onTheWay(String id, {required String idempotencyKey}) =>
      _api.post('/api/requests/$id/on-the-way',
          headers: {'Idempotency-Key': idempotencyKey});
  Future<void> start(String id, {required String idempotencyKey}) =>
      _api.post('/api/requests/$id/start',
          headers: {'Idempotency-Key': idempotencyKey});
  Future<void> updateNote(String id, String? note) =>
      _api.put('/api/requests/$id/note', data: {'note': note});
  Future<void> complete(String id, {required String idempotencyKey}) =>
      _api.post(
        '/api/requests/$id/complete',
        headers: {'Idempotency-Key': idempotencyKey},
      );

  Future<void> verifyCode(String id, String code, {required String idempotencyKey}) =>
      _api.post(
        '/api/requests/$id/verify-code',
        data: {'code': code},
        headers: {'Idempotency-Key': idempotencyKey},
      );

  Future<void> rate(String id, int score, String? comment) => _api.post(
    '/api/requests/$id/rating',
    data: {'score': score, 'comment': comment},
  );
}

class OfferActionResult {
  const OfferActionResult({this.requestId, this.status});
  final String? requestId, status;
  factory OfferActionResult.fromJson(Map<String, dynamic> json) =>
      OfferActionResult(
        requestId: json['requestId'] as String?,
        status: json['status'] as String?,
      );
}

abstract interface class OffersRepository {
  Future<List<PriceOfferModel>> mine({CancelToken? cancelToken});
  Future<OfferActionResult> action(
    String id,
    String action, {
    double? counterPrice,
    required String idempotencyKey,
  });
}

({String path, Map<String, dynamic>? body, Map<String, String> headers})
buildOfferActionTransport(
  String id,
  String action, {
  double? counterPrice,
  required String idempotencyKey,
}) => (
  path: '/api/offers/$id/$action',
  body: counterPrice == null ? null : {'counterPrice': counterPrice},
  headers: {'Idempotency-Key': idempotencyKey},
);

class OffersRepo implements OffersRepository {
  OffersRepo._();
  static final OffersRepo instance = OffersRepo._();

  final _api = ApiClient.instance;

  Future<PriceOfferModel> create({
    required String barberProfileId,
    required double proposedPrice,
    required DateTime requestedTime,
    required double lat,
    required double lng,
    String? note,
    required String idempotencyKey,
  }) async => PriceOfferModel.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/api/offers',
      data: {
        'barberProfileId': barberProfileId,
        'proposedPrice': proposedPrice,
        'requestedTime': requestedTime.toUtc().toIso8601String(),
        'lat': lat,
        'lng': lng,
        'note': note,
      },
      headers: {'Idempotency-Key': idempotencyKey},
    ),
  );

  @override
  Future<List<PriceOfferModel>> mine({CancelToken? cancelToken}) async {
    final data = await _api.get<List<dynamic>>(
      '/api/offers/mine',
      cancelToken: cancelToken,
    );
    return data
        .map((e) => PriceOfferModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<OfferActionResult> action(
    String id,
    String action, {
    double? counterPrice,
    required String idempotencyKey,
  }) async {
    final t = buildOfferActionTransport(
      id,
      action,
      counterPrice: counterPrice,
      idempotencyKey: idempotencyKey,
    );
    return OfferActionResult.fromJson(
      await _api.post<Map<String, dynamic>>(
        t.path,
        data: t.body,
        headers: t.headers,
      ),
    );
  }

  Future<OfferActionResult> accept(String id, String key) =>
      action(id, 'accept', idempotencyKey: key);
  Future<OfferActionResult> reject(String id, String key) =>
      action(id, 'reject', idempotencyKey: key);
  Future<OfferActionResult> counter(String id, double price, String key) =>
      action(id, 'counter', counterPrice: price, idempotencyKey: key);
  Future<PriceOfferModel> createFromRequest({
    required String serviceRequestId,
    required double price,
    DateTime? requestedTime,
    String? note,
    required String idempotencyKey,
  }) async => PriceOfferModel.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/api/offers/from-request',
      data: {
        'serviceRequestId': serviceRequestId,
        'price': price,
        if (requestedTime != null)
          'requestedTime': requestedTime.toUtc().toIso8601String(),
        'note': note,
      },
      headers: {'Idempotency-Key': idempotencyKey},
    ),
  );
  Future<OfferActionResult> acceptCounter(String id, String key) =>
      action(id, 'accept-counter', idempotencyKey: key);
  Future<OfferActionResult> rejectCounter(String id, String key) =>
      action(id, 'reject-counter', idempotencyKey: key);
}
