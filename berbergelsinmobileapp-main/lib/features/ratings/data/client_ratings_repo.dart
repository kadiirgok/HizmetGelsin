import '../../../core/api/api_client.dart';

class ClientRating {
  const ClientRating({
    required this.id,
    required this.requestId,
    required this.barberId,
    this.businessName,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.updatedAt,
    required this.moderationStatus,
    required this.version,
  });

  final String id, requestId, barberId, moderationStatus, version;
  final String? businessName, comment;
  final int rating;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isVisible => moderationStatus == 'Visible';
  bool get isEditable =>
      isVisible &&
      DateTime.now().toUtc().difference(createdAt.toUtc()) <=
          const Duration(hours: 168);

  factory ClientRating.fromJson(Map<String, dynamic> json) => ClientRating(
    id: json['id'] as String,
    requestId: json['requestId'] as String,
    barberId: json['barberId'] as String,
    businessName: json['businessName'] as String?,
    rating: json['rating'] as int,
    comment: json['comment'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String).toLocal(),
    moderationStatus: json['moderationStatus'] as String,
    version: json['version'] as String,
  );
}

class ClientRatingsPage {
  const ClientRatingsPage(
    this.items,
    this.page,
    this.pageSize,
    this.totalCount,
    this.hasNextPage,
  );
  final List<ClientRating> items;
  final int page, pageSize, totalCount;
  final bool hasNextPage;
}

enum RatingError {
  notFound,
  forbidden,
  notCompleted,
  alreadyExists,
  invalid,
  editWindowExpired,
  locked,
  reportInvalid,
  conflict,
  rateLimited,
  network,
}

RatingError mapRatingError(ApiException error) => switch (error.code) {
  'rating_not_found' => RatingError.notFound,
  'rating_forbidden' => RatingError.forbidden,
  'rating_request_not_completed' => RatingError.notCompleted,
  'rating_already_exists' => RatingError.alreadyExists,
  'rating_invalid' => RatingError.invalid,
  'rating_edit_window_expired' => RatingError.editWindowExpired,
  'rating_locked' => RatingError.locked,
  'rating_report_invalid' => RatingError.reportInvalid,
  'rating_conflict' => RatingError.conflict,
  'rating_rate_limited' => RatingError.rateLimited,
  _ => RatingError.network,
};

String ratingErrorMessage(RatingError error) => switch (error) {
  RatingError.notFound => 'Yorum bulunamadı.',
  RatingError.forbidden => 'Bu işlem için yetkiniz yok.',
  RatingError.notCompleted => 'Hizmet tamamlanmadan yorum yapılamaz.',
  RatingError.alreadyExists => 'Bu hizmet için daha önce yorum yaptınız.',
  RatingError.invalid => 'Puan veya yorum bilgilerini kontrol edin.',
  RatingError.editWindowExpired => 'Yorum düzenleme süresi dolmuş.',
  RatingError.locked => 'Bu yorum moderasyon nedeniyle düzenlenemiyor.',
  RatingError.reportInvalid => 'Rapor bilgilerini kontrol edin.',
  RatingError.conflict => 'Yorum başka bir yerde güncellendi. Liste yenilendi.',
  RatingError.rateLimited => 'Çok fazla işlem yapıldı. Lütfen biraz bekleyin.',
  RatingError.network =>
    'İşlem tamamlanamadı. Bağlantınızı kontrol edip tekrar deneyin.',
};

({String path, Map<String, dynamic>? body}) buildRatingTransport(
  String action,
  String id, {
  int? score,
  String? comment,
  String? version,
  String? reasonCode,
  String? description,
}) => (
  path: action == 'report' ? '/api/ratings/$id/report' : '/api/ratings/$id',
  body: action == 'update'
      ? {'score': score, 'comment': comment, 'version': version}
      : action == 'report'
      ? {'reasonCode': reasonCode, 'description': description}
      : null,
);

abstract interface class ClientRatingsRepository {
  Future<ClientRatingsPage> list({int page = 1, int pageSize = 20});
  Future<ClientRating> update(
    String id, {
    required int score,
    String? comment,
    required String version,
  });
  Future<void> delete(String id);
  Future<void> report(
    String id, {
    required String reasonCode,
    String? description,
  });
}

class ClientRatingsRepo implements ClientRatingsRepository {
  ClientRatingsRepo._();
  static final instance = ClientRatingsRepo._();
  final _api = ApiClient.instance;

  @override
  Future<ClientRatingsPage> list({int page = 1, int pageSize = 20}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/api/client/ratings',
      query: {'page': page, 'pageSize': pageSize},
    );
    final seen = <String>{};
    return ClientRatingsPage(
      (json['items'] as List)
          .map((e) => ClientRating.fromJson(e as Map<String, dynamic>))
          .where((e) => seen.add(e.id))
          .toList(),
      json['page'] as int,
      json['pageSize'] as int,
      json['totalCount'] as int,
      json['hasNextPage'] as bool,
    );
  }

  @override
  Future<ClientRating> update(
    String id, {
    required int score,
    String? comment,
    required String version,
  }) async {
    final transport = buildRatingTransport(
      'update',
      id,
      score: score,
      comment: comment,
      version: version,
    );
    return ClientRating.fromJson(
      await _api.put<Map<String, dynamic>>(
        transport.path,
        data: transport.body,
      ),
    );
  }

  @override
  Future<void> delete(String id) =>
      _api.delete(buildRatingTransport('delete', id).path);

  @override
  Future<void> report(
    String id, {
    required String reasonCode,
    String? description,
  }) {
    final transport = buildRatingTransport(
      'report',
      id,
      reasonCode: reasonCode,
      description: description,
    );
    return _api.post(transport.path, data: transport.body);
  }
}
