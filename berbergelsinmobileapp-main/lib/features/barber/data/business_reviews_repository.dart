import '../../../core/api/api_client.dart';
import '../../map/data/barbers_repo.dart';
import 'business_reviews.dart';

abstract interface class BusinessReviewsRepository {
  Future<BusinessReviewsPage> fetch({
    required int page,
    int pageSize = 20,
    int? rating,
  });
}

class ApiBusinessReviewsRepository implements BusinessReviewsRepository {
  ApiBusinessReviewsRepository({ApiClient? api})
    : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  @override
  Future<BusinessReviewsPage> fetch({
    required int page,
    int pageSize = 20,
    int? rating,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/barbers/me/reviews',
      query: {
        'page': page,
        'pageSize': pageSize,
        if (rating != null) 'rating': rating,
      },
    );
    final pageData = BusinessReviewsPage.fromJson(response);
    // Aynı müşterinin yorumlarını birleştir
    final merged = mergeBusinessReviewsByCustomer(pageData.items);
    return BusinessReviewsPage(
      items: merged,
      summary: pageData.summary,
      page: pageData.page,
      pageSize: pageData.pageSize,
      totalCount: pageData.totalCount,
      totalPages: pageData.totalPages,
    );
  }
}
