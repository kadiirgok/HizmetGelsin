import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/data/selection_options.dart';
import '../../barber/data/barber_customer_model.dart';

class TopService {
  const TopService({required this.name, required this.price});
  final String name;
  final double price;

  factory TopService.fromJson(Map<String, dynamic> json) => TopService(
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
  );
}

class NearbyBarber {
  NearbyBarber({
    required this.barberProfileId,
    this.businessName,
    this.firstName,
    this.category,
    this.description,
    this.serviceMode,
    this.city,
    this.district,
    this.neighborhood,
    required this.lat,
    required this.lng,
    required this.acceptsOffers,
    this.acceptsUrgentRequests = false,
    required this.distanceMeters,
    this.avgRating,
    this.ratingCount = 0,
    this.hasLogo = false,
    this.coverPhotoUrl,
    this.profileImageUrl,
    this.serviceCount = 0,
    this.minimumPrice,
    this.isOpenNow,
    this.serviceRadiusKm,
    this.topServices,
  });

  final String barberProfileId;
  final String? businessName;
  final String? firstName;
  final String? category;
  final String? description;
  final String? serviceMode;
  final String? city;
  final String? district;
  final String? neighborhood;
  double lat;
  double lng;
  final bool acceptsOffers;
  final bool acceptsUrgentRequests;
  final double distanceMeters;
  final double? avgRating;
  final int ratingCount;
  final bool hasLogo;
  final String? coverPhotoUrl;
  final String? profileImageUrl;
  final int serviceCount;
  final double? minimumPrice;
  final bool? isOpenNow;
  final int? serviceRadiusKm;
  final List<TopService>? topServices;

  String get displayName =>
      (businessName?.isNotEmpty == true ? businessName : firstName) ??
      'İşletme';

  factory NearbyBarber.fromJson(Map<String, dynamic> json) => NearbyBarber(
    barberProfileId: (json['barberProfileId'] ?? json['id']) as String,
    businessName: (json['businessName'] ?? json['name']) as String?,
    firstName: json['firstName'] as String?,
    category: json['category'] as String?,
    description: json['description'] as String?,
    serviceMode: json['serviceMode'] as String?,
    city: json['city'] as String?,
    district: json['district'] as String?,
    neighborhood: json['neighborhood'] as String?,
    lat: (json['lat'] as num?)?.toDouble() ?? 0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0,
    acceptsOffers: json['acceptsOffers'] as bool? ?? false,
    acceptsUrgentRequests: json['acceptsUrgentRequests'] as bool? ?? false,
    distanceMeters:
        (json['distanceMeters'] as num?)?.toDouble() ??
        ((json['distanceKm'] as num?)?.toDouble() ?? 0) * 1000,
    avgRating: (json['avgRating'] ?? json['rating'] as num?)?.toDouble(),
    ratingCount: (json['ratingCount'] ?? json['reviewCount']) as int? ?? 0,
    hasLogo: json['hasLogo'] as bool? ?? (json['profileImageUrl'] as String?)?.isNotEmpty == true ?? false,
    coverPhotoUrl: (json['coverPhotoUrl'] ?? json['coverImageUrl']) as String?,
    profileImageUrl: json['profileImageUrl'] as String?,
    serviceCount: json['serviceCount'] as int? ?? 0,
    minimumPrice: (json['minimumPrice'] as num?)?.toDouble(),
    topServices: (json['topServices'] as List?)
        ?.map((e) => TopService.fromJson(e as Map<String, dynamic>))
        .toList(),
    isOpenNow: json['isOpenNow'] as bool?,
    serviceRadiusKm: json['serviceRadiusKm'] as int?,
  );
}

enum DiscoverySort { distance, rating, priceAsc, priceDesc, relevance }

extension DiscoverySortApi on DiscoverySort {
  String get apiValue => switch (this) {
    DiscoverySort.distance => 'distance',
    DiscoverySort.rating => 'rating',
    DiscoverySort.priceAsc => 'price_asc',
    DiscoverySort.priceDesc => 'price_desc',
    DiscoverySort.relevance => 'relevance',
  };
}

class DiscoveryFilters {
  const DiscoveryFilters({
    this.query,
    this.category,
    this.serviceId,
    this.minPrice,
    this.maxPrice,
    this.minRating,
    this.serviceMode,
    this.availableAt,
    this.radiusKm = 30,
    this.sort = DiscoverySort.distance,
  });
  final String? query,
      category,
      serviceId,
      serviceMode;
  final double? minPrice, maxPrice, minRating;
  final DateTime? availableAt;
  final double radiusKm;
  final DiscoverySort sort;

  Map<String, dynamic> toQuery(
    double lat,
    double lng, {
    int page = 1,
    int pageSize = 20,
  }) => {
    'lat': lat,
    'lng': lng,
    'radiusKm': radiusKm.clamp(0.1, 50),
    if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
    if (category?.trim().isNotEmpty == true) 'category': category!.trim(),
    if (serviceId?.trim().isNotEmpty == true) 'serviceId': serviceId!.trim(),
    if (minPrice != null) 'minPrice': minPrice,
    if (maxPrice != null) 'maxPrice': maxPrice,
    if (minRating != null) 'minRating': minRating,
    if (serviceMode != null) 'serviceMode': serviceMode,
    if (availableAt != null)
      'availableAt': availableAt!.toUtc().toIso8601String(),
    'sort': sort.apiValue,
    'page': page,
    'pageSize': pageSize.clamp(1, 50),
  };
}

class DiscoveryPage {
  const DiscoveryPage(
    this.items,
    this.page,
    this.pageSize,
    this.totalCount,
    this.hasNextPage,
  );
  final List<NearbyBarber> items;
  final int page, pageSize, totalCount;
  final bool hasNextPage;
}

class ServiceCatalogItem {
  const ServiceCatalogItem({
    required this.id,
    required this.name,
    required this.categoryName,
    required this.isActive,
  });
  final String id, name, categoryName;
  final bool isActive;
  factory ServiceCatalogItem.fromJson(Map<String, dynamic> json) =>
      ServiceCatalogItem(
        id: json['id'] as String,
        name: json['name'] as String,
        categoryName: json['categoryName'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? false,
      );
}

class BarberServiceItem {
  BarberServiceItem({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.priceType = 'Fixed',
    this.durationMinutes,
    this.isPopular = false,
  });
  final String id;
  final String name;
  final double price;
  final String? description;
  final String priceType;
  final int? durationMinutes;
  final bool isPopular;

  factory BarberServiceItem.fromJson(Map<String, dynamic> json) =>
      BarberServiceItem(
        id: json['id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        description: json['description'] as String?,
        priceType: json['priceType'] as String? ?? 'Fixed',
        durationMinutes: json['durationMinutes'] as int?,
        isPopular: json['isPopular'] as bool? ?? false,
      );
}

class BusinessPhoto {
  BusinessPhoto({
    required this.id,
    required this.url,
    this.caption,
    this.isCover = false,
    this.sortOrder = 0,
  });

  final String id;
  final String url;
  final String? caption;
  final bool isCover;
  final int sortOrder;

  factory BusinessPhoto.fromJson(Map<String, dynamic> json) => BusinessPhoto(
    id: json['id'] as String,
    url: json['url'] as String,
    caption: json['caption'] as String?,
    isCover: json['isCover'] as bool? ?? false,
    sortOrder: json['sortOrder'] as int? ?? 0,
  );
}

class BusinessDashboard {
  BusinessDashboard({
    this.todayRequestCount = 0,
    this.pendingRequestCount = 0,
    this.activeRequestCount = 0,
    this.completedThisWeek = 0,
    this.completedTotal = 0,
    this.todayRevenue = 0,
    this.weekRevenue = 0,
    this.totalRevenue = 0,
    this.avgRating,
    this.ratingCount = 0,
    this.uniqueCustomerCount = 0,
    this.averageResponseMinutes = 0,
    this.weekAnsweredRequestCount = 0,
    this.conversionRate = 0,
  });

  final int todayRequestCount;
  final int pendingRequestCount;
  final int activeRequestCount;
  final int completedThisWeek;
  final int completedTotal;
  final double todayRevenue;
  final double weekRevenue;
  final double totalRevenue;
  final double? avgRating;
  final int ratingCount;
  final int uniqueCustomerCount;
  final int averageResponseMinutes;
  final int weekAnsweredRequestCount;
  final int conversionRate;

  factory BusinessDashboard.fromJson(Map<String, dynamic> json) =>
      BusinessDashboard(
        todayRequestCount: json['todayRequestCount'] as int? ?? 0,
        pendingRequestCount: json['pendingRequestCount'] as int? ?? 0,
        activeRequestCount: json['activeRequestCount'] as int? ?? 0,
        completedThisWeek: json['completedThisWeek'] as int? ?? 0,
        completedTotal: json['completedTotal'] as int? ?? 0,
        todayRevenue: (json['todayRevenue'] as num?)?.toDouble() ?? 0,
        weekRevenue: (json['weekRevenue'] as num?)?.toDouble() ?? 0,
        totalRevenue: (json['totalRevenue'] as num?)?.toDouble() ?? 0,
        avgRating: (json['avgRating'] as num?)?.toDouble(),
        ratingCount: json['ratingCount'] as int? ?? 0,
        uniqueCustomerCount: json['uniqueCustomerCount'] as int? ?? 0,
        averageResponseMinutes: json['averageResponseMinutes'] as int? ?? 0,
        weekAnsweredRequestCount: json['weekAnsweredRequestCount'] as int? ?? 0,
        conversionRate: json['conversionRate'] as int? ?? 0,
      );
}

class BarberReview {
  BarberReview({
    this.id,
    required this.score,
    this.comment,
    this.clientName,
    required this.createdAt,
    this.updatedAt,
    this.customerAvatarUrl,
    this.isOwn = false,
    this.version,
  });
  final String? id;
  final int score;
  final String? comment;
  final String? clientName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? customerAvatarUrl;
  final bool isOwn;
  final String? version;

  factory BarberReview.fromJson(Map<String, dynamic> json) => BarberReview(
    id: (json['id'] ?? json['ratingId']) as String?,
    score: (json['score'] ?? json['rating']) as int,
    comment: json['comment'] as String?,
    clientName: (json['customerDisplayName'] ?? json['clientName']) as String?,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String).toLocal(),
    customerAvatarUrl: json['customerAvatarUrl'] as String?,
    isOwn: json['isOwn'] as bool? ?? false,
    version: json['version'] as String?,
  );
}

/// Aynı müşterinin birden çok yorumunu teke düşürür:
/// puan ortalaması alınır, en son yorum ve tarih korunur.
List<BarberReview> mergeReviewsByCustomer(List<BarberReview> reviews) {
  final merged = <String, List<BarberReview>>{};
  for (final r in reviews) {
    final key = (r.clientName ?? '').trim().toLowerCase();
    if (key.isEmpty) continue;
    merged.putIfAbsent(key, () => []).add(r);
  }
  return merged.values.map((group) {
    group.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final avg = group.fold<int>(0, (s, r) => s + r.score) ~/ group.length;
    final latest = group.first;
    final latestComment = group
        .map((r) => r.comment)
        .where((c) => c != null && c.trim().isNotEmpty)
        .lastOrNull;
    return BarberReview(
      id: latest.id,
      score: avg.clamp(0, 5),
      comment: latestComment,
      clientName: latest.clientName,
      createdAt:
          group.map((r) => r.createdAt).reduce((a, b) => a.isAfter(b) ? a : b),
      updatedAt: latest.updatedAt,
      customerAvatarUrl: latest.customerAvatarUrl,
    );
  }).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

class BarberReviewsPage {
  const BarberReviewsPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.hasNextPage,
    this.averageRating,
  });
  final List<BarberReview> items;
  final int page, pageSize, totalCount;
  final bool hasNextPage;
  final double? averageRating;

  factory BarberReviewsPage.fromJson(Map<String, dynamic> json) =>
      BarberReviewsPage(
        items: (json['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => BarberReview.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
        page: json['page'] as int? ?? 1,
        pageSize: json['pageSize'] as int? ?? 20,
        totalCount: json['totalCount'] as int? ?? 0,
        hasNextPage: json['hasNextPage'] as bool? ?? false,
        averageRating: (json['averageRating'] as num?)?.toDouble(),
      );
}

class AvailabilityInterval {
  const AvailabilityInterval(this.open, this.close);
  final String open, close;
  factory AvailabilityInterval.fromJson(Map<String, dynamic> json) =>
      AvailabilityInterval(json['open'] as String, json['close'] as String);
}

class BarberAvailabilitySummary {
  const BarberAvailabilitySummary({
    required this.barberProfileId,
    required this.date,
    required this.timeZone,
    required this.isWorkingDay,
    required this.isOpenNow,
    required this.workingIntervals,
    required this.precision,
  });
  final String barberProfileId, timeZone, precision;
  final DateTime date;
  final bool isWorkingDay, isOpenNow;
  final List<AvailabilityInterval> workingIntervals;
  factory BarberAvailabilitySummary.fromJson(Map<String, dynamic> json) =>
      BarberAvailabilitySummary(
        barberProfileId: json['barberProfileId'] as String,
        date: DateTime.parse(json['date'] as String),
        timeZone: json['timeZone'] as String,
        isWorkingDay: json['isWorkingDay'] as bool? ?? false,
        isOpenNow: json['isOpenNow'] as bool? ?? false,
        workingIntervals: (json['workingIntervals'] as List? ?? [])
            .whereType<Map>()
            .map(
              (e) =>
                  AvailabilityInterval.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(growable: false),
        precision: json['precision'] as String? ?? 'working_hours_only',
      );
}

class BarberDetail {
  BarberDetail({
    required this.barberProfileId,
    this.businessName,
    this.firstName,
    this.lastName,
    this.category,
    this.description,
    this.serviceMode = 'Mobile',
    this.city,
    this.district,
    this.neighborhood,
    this.addressLine,
    required this.workingHours,
    required this.acceptsOffers,
    this.acceptsUrgentRequests = false,
    this.phoneNumber,
    required this.services,
    this.photos = const [],
    this.badges = const [],
    this.lat,
    this.lng,
    this.avgRating,
    this.ratingCount = 0,
    this.hasLogo = false,
    this.reviews = const [],
    this.coverImageUrl,
    this.profileImageUrl,
    this.isOpenNow = false,
    this.serviceRadiusKm = 0,
  });

  final String barberProfileId;
  final String? businessName;
  final String? firstName;
  final String? lastName;
  final String? category;
  final String? description;
  final String serviceMode;
  final String? city;
  final String? district;
  final String? neighborhood;
  final String? addressLine;
  final String workingHours;
  final bool acceptsOffers;
  final bool acceptsUrgentRequests;
  final String? phoneNumber;
  final List<BarberServiceItem> services;
  final List<BusinessPhoto> photos;
  final List<String> badges;
  final double? lat;
  final double? lng;
  final double? avgRating;
  final int ratingCount;
  final bool hasLogo;
  final List<BarberReview> reviews;
  final String? coverImageUrl;
  final String? profileImageUrl;
  final bool isOpenNow;
  final int serviceRadiusKm;

  String get displayName =>
      (businessName?.isNotEmpty == true
          ? businessName
          : '$firstName $lastName') ??
      'İşletme';

  factory BarberDetail.fromJson(Map<String, dynamic> json) => BarberDetail(
    barberProfileId: json['barberProfileId'] as String,
    businessName: json['businessName'] as String?,
    firstName: json['firstName'] as String?,
    lastName: json['lastName'] as String?,
    category: json['category'] as String?,
    description: json['description'] as String?,
    serviceMode: json['serviceMode'] as String? ?? 'Mobile',
    city: json['city'] as String?,
    district: json['district'] as String?,
    neighborhood: json['neighborhood'] as String?,
    addressLine: json['addressLine'] as String?,
    workingHours: json['workingHours'] as String? ?? '[]',
    acceptsOffers: json['acceptsOffers'] as bool,
    acceptsUrgentRequests: json['acceptsUrgentRequests'] as bool? ?? false,
    phoneNumber: json['phoneNumber'] as String?,
    services: (json['services'] as List)
        .map((s) => BarberServiceItem.fromJson(s as Map<String, dynamic>))
        .toList(),
    photos: (json['photos'] as List? ?? [])
        .map((p) => BusinessPhoto.fromJson(p as Map<String, dynamic>))
        .toList(),
    badges: (json['badges'] as List? ?? []).cast<String>(),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    avgRating: (json['avgRating'] as num?)?.toDouble(),
    ratingCount: json['ratingCount'] as int? ?? 0,
    hasLogo: json['hasLogo'] as bool? ?? (json['profileImageUrl'] as String?)?.isNotEmpty == true ?? false,
    reviews: (json['reviews'] as List? ?? [])
        .map((r) => BarberReview.fromJson(r as Map<String, dynamic>))
        .toList(),
    coverImageUrl: json['coverImageUrl'] as String?,
    profileImageUrl: json['profileImageUrl'] as String?,
    isOpenNow: json['isOpenNow'] as bool? ?? false,
    serviceRadiusKm: json['serviceRadiusKm'] as int? ?? 0,
  );
}

Map<String, dynamic> buildBarberProfileUpdatePayload({
  String? businessName,
  String? category,
  String? description,
  String? serviceMode,
  String? city,
  String? district,
  String? neighborhood,
  String? addressLine,
  required bool sharePhone,
  required bool acceptsOffers,
  required bool acceptsUrgentRequests,
  required int serviceRadiusKm,
  List<Map<String, dynamic>>? workingHours,
}) => {
  'businessName': businessName,
  'category': category,
  'description': description,
  'serviceMode': serviceMode,
  'city': city,
  'district': district,
  'neighborhood': neighborhood,
  'addressLine': addressLine,
  'sharePhone': sharePhone,
  'acceptsOffers': acceptsOffers,
  'acceptsUrgentRequests': acceptsUrgentRequests,
  'serviceRadiusKm': serviceRadiusKm,
  if (workingHours != null) 'workingHours': workingHours,
};

abstract interface class DiscoveryRepository {
  Future<DiscoveryPage> discover(
    double lat,
    double lng,
    DiscoveryFilters filters, {
    int page = 1,
    int pageSize = 20,
    CancelToken? cancelToken,
  });
}

abstract interface class BarberDetailRepository {
  Future<BarberDetail> detail(String barberProfileId);
  Future<BarberReviewsPage> reviews(
    String barberProfileId, {
    int page = 1,
    int pageSize = 20,
  });
  Future<BarberAvailabilitySummary> availability(
    String barberProfileId,
    DateTime date,
  );
  Future<List<int>> logoBytes(String barberProfileId);
}

class BarbersRepo implements DiscoveryRepository, BarberDetailRepository {
  BarbersRepo._();
  static final BarbersRepo instance = BarbersRepo._();

  final _api = ApiClient.instance;

  Future<List<CategoryGroup>> categoryGroups() async {
    try {
      final data = await _api.get<List<dynamic>>('/api/categories');
      return data
          .map((e) => CategoryGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> categories() async {
    try {
      final data = await _api.get<List<dynamic>>('/api/barbers/categories');
      final items = data
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return items.isEmpty ? ServiceSelectionOptions.categories : items;
    } catch (_) {
      return ServiceSelectionOptions.categories;
    }
  }

  Future<List<ServiceCatalogItem>> serviceCatalog({
    String? category,
    String? query,
  }) async {
    final data = await _api.get<List<dynamic>>(
      '/api/services/catalog',
      query: {
        if (category?.trim().isNotEmpty == true) 'category': category!.trim(),
        if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
      },
    );
    return data
        .whereType<Map>()
        .map((e) => ServiceCatalogItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.isActive)
        .toList(growable: false);
  }

  Future<List<NearbyBarber>> nearby(
    double lat,
    double lng, {
    String? query,
    String? category,
    String? city,
    String? district,
    String? neighborhood,
  }) async {
    final data = await _api.get<List<dynamic>>(
      '/api/barbers/nearby',
      query: {
        'lat': lat,
        'lng': lng,
        if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
        if (category?.trim().isNotEmpty == true) 'category': category!.trim(),
        if (city?.trim().isNotEmpty == true) 'city': city!.trim(),
        if (district?.trim().isNotEmpty == true) 'district': district!.trim(),
        if (neighborhood?.trim().isNotEmpty == true)
          'neighborhood': neighborhood!.trim(),
      },
    );
    return data
        .map((e) => NearbyBarber.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<DiscoveryPage> discover(
    double lat,
    double lng,
    DiscoveryFilters filters, {
    int page = 1,
    int pageSize = 20,
    CancelToken? cancelToken,
  }) async {
    final data = await _api.get<dynamic>(
      '/api/barbers/nearby',
      query: filters.toQuery(lat, lng, page: page, pageSize: pageSize),
      cancelToken: cancelToken,
    );
    print('DISCOVER_DEBUG: data type=${data.runtimeType}, isList=${data is List}, isMap=${data is Map}');
    if (data is List) {
      final items = _uniqueBarbers(data);
      print('DISCOVER_DEBUG: List path, items=${items.length}');
      return DiscoveryPage(items, 1, items.length, items.length, false);
    }
    if (data is! Map || data['items'] is! List) {
      print('DISCOVER_DEBUG: Invalid response, throwing');
      throw ApiException(
        'Keşif yanıtı okunamadı.',
        kind: ApiErrorKind.invalidResponse,
      );
    }
    final rawItems = data['items'] as List;
    print('DISCOVER_DEBUG: Map path, rawItems=${rawItems.length}, page=${data['page']}');
    final items = _uniqueBarbers(rawItems);
    print('DISCOVER_DEBUG: Parsed items=${items.length}');
    return DiscoveryPage(
      items,
      data['page'] as int? ?? page,
      data['pageSize'] as int? ?? pageSize,
      data['totalCount'] as int? ?? items.length,
      data['hasNextPage'] as bool? ?? false,
    );
  }

  static List<NearbyBarber> _uniqueBarbers(List<dynamic> data) {
    final result = <String, NearbyBarber>{};
    for (final raw in data.whereType<Map>()) {
      final item = NearbyBarber.fromJson(Map<String, dynamic>.from(raw));
      result[item.barberProfileId] = item;
    }
    return result.values.toList();
  }

  @override
  Future<BarberDetail> detail(String barberProfileId) async =>
      BarberDetail.fromJson(
        await _api.get<Map<String, dynamic>>('/api/barbers/$barberProfileId'),
      );

  @override
  Future<BarberReviewsPage> reviews(
    String barberProfileId, {
    int page = 1,
    int pageSize = 20,
  }) async => BarberReviewsPage.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/api/barbers/$barberProfileId/reviews',
      query: {'page': page, 'pageSize': pageSize.clamp(1, 50)},
    ),
  );

  @override
  Future<BarberAvailabilitySummary> availability(
    String barberProfileId,
    DateTime date,
  ) async => BarberAvailabilitySummary.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/api/barbers/$barberProfileId/availability-summary',
      query: {
        'date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      },
    ),
  );

  /// İşletme logosu (Bearer'lı byte indirme; Image.memory ile gösterilir)
  @override
  Future<List<int>> logoBytes(String barberProfileId) =>
      _api.getBytes('/api/barbers/$barberProfileId/logo');

  // İşletme tarafı
  Future<Map<String, dynamic>> myProfile() =>
      _api.get<Map<String, dynamic>>('/api/barbers/me/profile');

  Future<BusinessDashboard> myDashboard() async => BusinessDashboard.fromJson(
    await _api.get<Map<String, dynamic>>('/api/barbers/me/dashboard'),
  );

  Future<BarberReviewsPage> myReviews() async =>
      BarberReviewsPage.fromJson(
        await _api.get<Map<String, dynamic>>('/api/barbers/me/reviews'),
      );

  Future<CustomerPage> myCustomers({int page = 1, int pageSize = 50}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/api/barbers/me/customers?page=$page&pageSize=$pageSize',
    );
    return CustomerPage.fromJson(data);
  }

  Future<void> setOnline(bool isOnline) =>
      _api.put('/api/barbers/me/online', data: {'isOnline': isOnline});

  Future<void> updateLocation(double lat, double lng) =>
      _api.put('/api/barbers/me/location', data: {'lat': lat, 'lng': lng});

  Future<void> updateProfile({
    String? businessName,
    String? category,
    String? description,
    String? serviceMode,
    String? city,
    String? district,
    String? neighborhood,
    String? addressLine,
    required bool sharePhone,
    required bool acceptsOffers,
    required bool acceptsUrgentRequests,
    required int serviceRadiusKm,
    List<Map<String, dynamic>>? workingHours,
  }) => _api.put(
    '/api/barbers/me/profile',
    data: buildBarberProfileUpdatePayload(
      businessName: businessName,
      category: category,
      description: description,
      serviceMode: serviceMode,
      city: city,
      district: district,
      neighborhood: neighborhood,
      addressLine: addressLine,
      sharePhone: sharePhone,
      acceptsOffers: acceptsOffers,
      acceptsUrgentRequests: acceptsUrgentRequests,
      serviceRadiusKm: serviceRadiusKm,
      workingHours: workingHours,
    ),
  );

  Future<void> uploadLogo(
    List<int> bytes,
    String fileName,
    String contentType,
  ) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    await _api.postMultipart('/api/barbers/me/logo', formData);
  }

  Future<BarberServiceItem> addService(
    String name,
    double price, {
    String? description,
    String priceType = 'Fixed',
    int? durationMinutes,
    bool isPopular = false,
  }) async => BarberServiceItem.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/api/barbers/me/services',
      data: {
        'name': name,
        'price': price,
        'description': description,
        'priceType': priceType,
        'durationMinutes': durationMinutes,
        'isPopular': isPopular,
      },
    ),
  );

  Future<void> updateService(
    String id,
    String name,
    double price, {
    String? description,
    String priceType = 'Fixed',
    int? durationMinutes,
    bool isPopular = false,
  }) => _api.put(
    '/api/barbers/me/services/$id',
    data: {
      'name': name,
      'price': price,
      'description': description,
      'priceType': priceType,
      'durationMinutes': durationMinutes,
      'isPopular': isPopular,
    },
  );

  Future<void> deleteService(String id) =>
      _api.delete('/api/barbers/me/services/$id');

  Future<BusinessPhoto> uploadPhoto(
    List<int> bytes,
    String fileName,
    String contentType, {
    String? caption,
    bool isCover = false,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(contentType),
      ),
      'caption': caption,
      'isCover': isCover,
    });
    return BusinessPhoto.fromJson(
      await _api.postMultipart<Map<String, dynamic>>(
        '/api/barbers/me/photos',
        formData,
      ),
    );
  }

  Future<void> setCoverPhoto(String id) =>
      _api.put('/api/barbers/me/photos/$id/cover');

  Future<void> deletePhoto(String id) =>
      _api.delete('/api/barbers/me/photos/$id');
}

// ── Hiyerarşik Kategori Modelleri ──

class CategoryGroup {
  final String id;
  final String name;
  final String? icon;
  final List<SubCategory> categories;

  const CategoryGroup({
    required this.id,
    required this.name,
    this.icon,
    required this.categories,
  });

  factory CategoryGroup.fromJson(Map<String, dynamic> json) => CategoryGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String?,
    categories: (json['categories'] as List<dynamic>)
        .map((e) => SubCategory.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class SubCategory {
  final String id;
  final String name;
  final int sortOrder;

  const SubCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory SubCategory.fromJson(Map<String, dynamic> json) => SubCategory(
    id: json['id'] as String,
    name: json['name'] as String,
    sortOrder: json['sortOrder'] as int? ?? 0,
  );
}
