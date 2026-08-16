import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';

class FavoriteBusiness {
  const FavoriteBusiness({
    required this.id,
    this.name,
    this.category,
    this.city,
    this.district,
    this.rating,
    required this.reviewCount,
    this.coverImageUrl,
    this.profileImageUrl,
    this.minimumPrice,
    required this.isOpenNow,
    required this.favoritedAt,
  });
  final String id;
  final String? name, category, city, district, coverImageUrl, profileImageUrl;
  final double? rating, minimumPrice;
  final int reviewCount;
  final bool isOpenNow;
  final DateTime favoritedAt;
  factory FavoriteBusiness.fromJson(Map<String, dynamic> j) => FavoriteBusiness(
    id: j['id'] as String,
    name: j['name'] as String?,
    category: j['category'] as String?,
    city: j['city'] as String?,
    district: j['district'] as String?,
    rating: (j['rating'] as num?)?.toDouble(),
    reviewCount: j['reviewCount'] as int? ?? 0,
    coverImageUrl: j['coverImageUrl'] as String?,
    profileImageUrl: j['profileImageUrl'] as String?,
    minimumPrice: (j['minimumPrice'] as num?)?.toDouble(),
    isOpenNow: j['isOpenNow'] as bool? ?? false,
    favoritedAt: DateTime.parse(j['favoritedAt'] as String),
  );
}

class FavoritePage {
  const FavoritePage(this.items, this.page, this.hasNextPage);
  final List<FavoriteBusiness> items;
  final int page;
  final bool hasNextPage;
}

enum FavoriteError {
  notFound,
  forbidden,
  businessUnavailable,
  conflict,
  rateLimited,
  invalidQuery,
  network,
}

FavoriteError mapFavoriteError(ApiException e) => switch (e.code) {
  'favorite_not_found' => FavoriteError.notFound,
  'favorite_forbidden' => FavoriteError.forbidden,
  'favorite_business_unavailable' => FavoriteError.businessUnavailable,
  'favorite_conflict' => FavoriteError.conflict,
  'favorite_rate_limited' => FavoriteError.rateLimited,
  'favorite_invalid_query' => FavoriteError.invalidQuery,
  _ => FavoriteError.network,
};
String favoriteErrorMessage(FavoriteError e) => switch (e) {
  FavoriteError.notFound => 'Favori bulunamadı.',
  FavoriteError.forbidden => 'Bu işlem için yetkiniz yok.',
  FavoriteError.businessUnavailable => 'İşletme artık kullanılamıyor.',
  FavoriteError.conflict => 'Favori başka bir yerde güncellendi.',
  FavoriteError.rateLimited => 'Çok fazla işlem yapıldı. Lütfen bekleyin.',
  FavoriteError.invalidQuery => 'Liste isteği geçersiz.',
  FavoriteError.network => 'Favoriler güncellenemedi. Tekrar deneyin.',
};

abstract interface class FavoritesRepository {
  Future<FavoritePage> list({int page = 1, int pageSize = 20});
  Future<bool> status(String id);
  Future<void> add(String id);
  Future<void> remove(String id);
}

class FavoritesRepo implements FavoritesRepository {
  FavoritesRepo._();
  static final instance = FavoritesRepo._();
  final _api = ApiClient.instance;
  @override
  Future<FavoritePage> list({int page = 1, int pageSize = 20}) async {
    final j = await _api.get<Map<String, dynamic>>(
      '/api/client/favorites',
      query: {'page': page, 'pageSize': pageSize},
    );
    final seen = <String>{};
    return FavoritePage(
      (j['items'] as List)
          .map((e) => FavoriteBusiness.fromJson(e as Map<String, dynamic>))
          .where((e) => seen.add(e.id))
          .toList(),
      j['page'] as int,
      j['hasNextPage'] as bool,
    );
  }

  @override
  Future<bool> status(String id) async =>
      (await _api.get<Map<String, dynamic>>(
            '/api/client/favorites/$id/status',
          ))['isFavorite']
          as bool;
  @override
  Future<void> add(String id) => _api.post('/api/client/favorites/$id');
  @override
  Future<void> remove(String id) => _api.delete('/api/client/favorites/$id');
}

class FavoriteStore extends ChangeNotifier {
  FavoriteStore._();
  static final instance = FavoriteStore._();
  FavoritesRepository repository = FavoritesRepo.instance;
  final ids = <String>{};
  final busy = <String>{};
  bool loaded = false;
  void clearSession() {
    ids.clear();
    busy.clear();
    loaded = false;
    notifyListeners();
  }

  void sync(String id, bool value) {
    value ? ids.add(id) : ids.remove(id);
    notifyListeners();
  }

  Future<void> loadIds() async {
    if (loaded) return;
    var p = 1;
    do {
      final x = await repository.list(page: p, pageSize: 50);
      ids.addAll(x.items.map((e) => e.id));
      p++;
      if (!x.hasNextPage) break;
    } while (p < 20);
    loaded = true;
    notifyListeners();
  }

  Future<bool> toggle(String id) async {
    if (!busy.add(id)) return ids.contains(id);
    final old = ids.contains(id);
    old ? ids.remove(id) : ids.add(id);
    notifyListeners();
    try {
      old ? await repository.remove(id) : await repository.add(id);
      return !old;
    } catch (_) {
      old ? ids.add(id) : ids.remove(id);
      rethrow;
    } finally {
      busy.remove(id);
      notifyListeners();
    }
  }
}
