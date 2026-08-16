class BusinessReview {
  const BusinessReview({
    required this.id,
    required this.rating,
    required this.createdAt,
    required this.customerDisplayName,
    required this.serviceRequestId,
    this.comment,
    this.customerAvatarUrl,
    this.serviceName,
  });

  final String id;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String customerDisplayName;
  final String? customerAvatarUrl;
  final String? serviceName;
  final String serviceRequestId;

  factory BusinessReview.fromJson(Map<String, dynamic> json) {
    final rawRating = (json['rating'] as num?)?.toInt() ?? 0;
    return BusinessReview(
      id: json['id']?.toString() ?? '',
      rating: rawRating.clamp(0, 5),
      comment: json['comment'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      customerDisplayName:
          (json['customerDisplayName'] as String?)?.trim().isNotEmpty == true
          ? (json['customerDisplayName'] as String).trim()
          : 'Müşteri',
      customerAvatarUrl: json['customerAvatarUrl'] as String?,
      serviceName: json['serviceName'] as String?,
      serviceRequestId: json['serviceRequestId']?.toString() ?? '',
    );
  }
}

class BusinessReviewsSummary {
  const BusinessReviewsSummary({
    required this.averageRating,
    required this.totalCount,
    required this.ratingDistribution,
  });

  final double averageRating;
  final int totalCount;
  final Map<int, int> ratingDistribution;

  static const empty = BusinessReviewsSummary(
    averageRating: 0,
    totalCount: 0,
    ratingDistribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
  );

  factory BusinessReviewsSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    final rawDistribution = json['ratingDistribution'];
    final distribution = <int, int>{};
    for (var score = 1; score <= 5; score++) {
      final value = rawDistribution is Map
          ? rawDistribution[score.toString()] ?? rawDistribution[score]
          : null;
      distribution[score] = (value as num?)?.toInt() ?? 0;
    }
    final average = (json['averageRating'] as num?)?.toDouble() ?? 0;
    return BusinessReviewsSummary(
      averageRating: average.isFinite ? average.clamp(0, 5) : 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      ratingDistribution: distribution,
    );
  }
}

/// Aynı müşterinin birden çok yorumunu teke düşürür:
/// puan ortalaması alınır, en son yazılan yorum ve tarih korunur.
List<BusinessReview> mergeBusinessReviewsByCustomer(
  List<BusinessReview> reviews,
) {
  final merged = <String, List<BusinessReview>>{};
  for (final r in reviews) {
    final key = r.customerDisplayName.trim().toLowerCase();
    if (key.isEmpty) continue;
    merged.putIfAbsent(key, () => []).add(r);
  }
  return merged.values.map((group) {
    group.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final avg = group.fold<int>(0, (s, r) => s + r.rating) ~/ group.length;
    final latest = group.first;
    final latestComment = group
        .map((r) => r.comment)
        .where((c) => c != null && c.trim().isNotEmpty)
        .lastOrNull;
    return BusinessReview(
      id: latest.id,
      rating: avg.clamp(0, 5),
      comment: latestComment,
      createdAt:
          group.map((r) => r.createdAt).reduce((a, b) => a.isAfter(b) ? a : b),
      customerDisplayName: latest.customerDisplayName,
      customerAvatarUrl: latest.customerAvatarUrl,
      serviceName: '${group.length} işlem değerlendirmesi',
      serviceRequestId: latest.serviceRequestId,
    );
  }).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

class BusinessReviewsPage {
  const BusinessReviewsPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
    required this.summary,
  });

  final List<BusinessReview> items;
  final int page;
  final int pageSize;
  final int totalCount;
  final int totalPages;
  final BusinessReviewsSummary summary;

  factory BusinessReviewsPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];
    return BusinessReviewsPage(
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => BusinessReview.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      summary: BusinessReviewsSummary.fromJson(
        json['summary'] is Map
            ? Map<String, dynamic>.from(json['summary'] as Map)
            : null,
      ),
    );
  }
}
