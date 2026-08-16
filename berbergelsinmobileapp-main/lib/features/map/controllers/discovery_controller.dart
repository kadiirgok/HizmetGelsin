import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../data/barbers_repo.dart';

enum DiscoveryStatus {
  initial,
  loading,
  refreshing,
  loadingMore,
  success,
  empty,
  error,
  locationPermissionRequired,
  locationUnavailable,
  rateLimited,
}

class DiscoveryController extends ChangeNotifier {
  DiscoveryController({DiscoveryRepository? repository})
    : _repository = repository ?? BarbersRepo.instance;
  static final shared = DiscoveryController();
  final DiscoveryRepository _repository;
  DiscoveryStatus status = DiscoveryStatus.initial;
  DiscoveryFilters filters = const DiscoveryFilters();
  List<NearbyBarber> items = const [];
  int page = 0;
  bool hasNextPage = false;
  int totalCount = 0;
  double? latitude, longitude;
  CancelToken? _cancelToken;
  int _generation = 0;
  Timer? _autoRefreshTimer;
  static const _autoRefreshInterval = Duration(seconds: 30);

  void setLocation(double lat, double lng) {
    latitude = lat;
    longitude = lng;
  }

  void locationRequired() {
    status = DiscoveryStatus.locationPermissionRequired;
    notifyListeners();
  }

  void locationUnavailable() {
    status = DiscoveryStatus.locationUnavailable;
    notifyListeners();
  }

  Future<void> applyFilters(DiscoveryFilters value) async {
    filters = value;
    await load();
  }

  Future<void> load({bool refresh = false}) async {
    if (latitude == null || longitude == null) {
      locationRequired();
      return;
    }
    _cancelToken?.cancel('superseded');
    final token = _cancelToken = CancelToken();
    final generation = ++_generation;
    status = refresh ? DiscoveryStatus.refreshing : DiscoveryStatus.loading;
    if (!refresh) items = const [];
    page = 0;
    hasNextPage = false;
    notifyListeners();
    try {
      final result = await _repository.discover(
        latitude!,
        longitude!,
        filters,
        page: 1,
        cancelToken: token,
      );
      if (generation != _generation) return;
      items = result.items;
      page = result.page;
      hasNextPage = result.hasNextPage;
      totalCount = result.totalCount;
      status = items.isEmpty ? DiscoveryStatus.empty : DiscoveryStatus.success;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _setError(e);
    } catch (e, st) {
      if (generation == _generation) _setError(e);
    }
    if (generation == _generation) notifyListeners();
  }

  Future<void> loadMore() async {
    if (!hasNextPage ||
        status == DiscoveryStatus.loadingMore ||
        latitude == null) {
      return;
    }
    final token = _cancelToken = CancelToken();
    final generation = _generation;
    status = DiscoveryStatus.loadingMore;
    notifyListeners();
    try {
      final result = await _repository.discover(
        latitude!,
        longitude!,
        filters,
        page: page + 1,
        cancelToken: token,
      );
      if (generation != _generation) return;
      final merged = <String, NearbyBarber>{
        for (final item in items) item.barberProfileId: item,
      };
      for (final item in result.items) {
        merged[item.barberProfileId] = item;
      }
      items = merged.values.toList();
      page = result.page;
      hasNextPage = result.hasNextPage;
      totalCount = result.totalCount;
      status = DiscoveryStatus.success;
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) _setError(e);
    } catch (e) {
      _setError(e);
    }
    notifyListeners();
  }

  void _setError(Object error) {
    if (error is ApiException &&
        (error.statusCode == 429 || error.code == 'discovery_rate_limited')) {
      status = DiscoveryStatus.rateLimited;
      return;
    }
    status = DiscoveryStatus.error;
  }

  void startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (status != DiscoveryStatus.loading &&
          status != DiscoveryStatus.refreshing) {
        load(refresh: true);
      }
    });
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  String get safeErrorMessage => switch (status) {
    DiscoveryStatus.rateLimited =>
      'Çok sık arama yaptınız. Kısa bir süre sonra tekrar deneyin.',
    DiscoveryStatus.locationPermissionRequired =>
      'Yakındaki işletmeleri göstermek için konum izni gerekli.',
    DiscoveryStatus.locationUnavailable =>
      'Konum alınamadı. Lütfen konum servisini açıp tekrar deneyin.',
    _ => 'İşletmeler yüklenemedi. Lütfen tekrar deneyin.',
  };

  @override
  void dispose() {
    _cancelToken?.cancel('disposed');
    _autoRefreshTimer?.cancel();
    super.dispose();
  }
}
