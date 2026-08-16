import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../data/address_search_repository.dart';

enum AddressSearchStatus {
  initial,
  typing,
  loading,
  results,
  empty,
  networkError,
  rateLimited,
  providerUnavailable,
  incomplete,
  selected,
  cleared,
}

typedef SessionTokenFactory = String Function();

class AddressSearchController extends ChangeNotifier {
  AddressSearchController({
    required AddressSearchRepository repository,
    Duration debounce = const Duration(milliseconds: 400),
    SessionTokenFactory? tokenFactory,
  }) : _repository = repository,
       _debounceDuration = debounce,
       _tokenFactory = tokenFactory ?? _newUuid;
  final AddressSearchRepository _repository;
  final Duration _debounceDuration;
  final SessionTokenFactory _tokenFactory;
  Timer? _debounce;
  CancelToken? _request;
  bool _disposed = false;
  int _generation = 0;
  AddressSearchStatus status = AddressSearchStatus.initial;
  List<AddressSuggestion> suggestions = const [];
  ResolvedAddress? selectedAddress;
  String? sessionToken;
  String query = '';

  void focus() {
    sessionToken ??= _tokenFactory();
  }

  void queryChanged(String value) {
    query = value.trim();
    _debounce?.cancel();
    _cancelRequest();
    suggestions = const [];
    if (query.isEmpty) {
      sessionToken = null;
      selectedAddress = null;
      status = AddressSearchStatus.cleared;
      _notify();
      return;
    }
    focus();
    if (query.length < 3) {
      status = AddressSearchStatus.typing;
      _notify();
      return;
    }
    status = AddressSearchStatus.typing;
    _notify();
    final expected = query;
    _debounce = Timer(_debounceDuration, () => _search(expected));
  }

  Future<void> retry() async {
    if (query.length >= 3) await _search(query);
  }

  Future<void> _search(String expected) async {
    if (_disposed || expected != query) return;
    _cancelRequest();
    final token = sessionToken ??= _tokenFactory();
    final request = _request = CancelToken();
    final generation = ++_generation;
    status = AddressSearchStatus.loading;
    _notify();
    try {
      final result = await _repository.suggestions(expected, token, request);
      if (!_current(request, generation)) return;
      suggestions = result;
      status = result.isEmpty
          ? AddressSearchStatus.empty
          : AddressSearchStatus.results;
      _notify();
    } catch (error) {
      if (!_current(request, generation) || request.isCancelled) return;
      status = _safeError(error);
      _notify();
    }
  }

  Future<ResolvedAddress?> select(AddressSuggestion suggestion) async {
    final token = sessionToken;
    if (token == null) return null;
    _debounce?.cancel();
    _cancelRequest();
    final request = _request = CancelToken();
    final generation = ++_generation;
    status = AddressSearchStatus.loading;
    _notify();
    try {
      final result = await _repository.details(
        suggestion.placeId,
        token,
        request,
      );
      if (!_current(request, generation)) return null;
      if (result.countryCode != null && result.countryCode != 'TR') {
        status = AddressSearchStatus.empty;
        _notify();
        return null;
      }
      selectedAddress = result;
      suggestions = const [];
      query = result.formattedAddress ?? suggestion.displayText;
      status = result.province == null || result.district == null
          ? AddressSearchStatus.incomplete
          : AddressSearchStatus.selected;
      sessionToken = null;
      _request = null;
      _notify();
      return result;
    } catch (error) {
      if (!_current(request, generation) || request.isCancelled) return null;
      status = _safeError(error);
      _notify();
      return null;
    }
  }

  AddressSearchStatus _safeError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 429) return AddressSearchStatus.rateLimited;
      if (error.statusCode == 502 || error.statusCode == 503) {
        return AddressSearchStatus.providerUnavailable;
      }
      if (error.statusCode == 422) return AddressSearchStatus.incomplete;
    }
    return AddressSearchStatus.networkError;
  }

  bool _current(CancelToken request, int generation) =>
      !_disposed && identical(_request, request) && generation == _generation;
  void _cancelRequest() {
    _request?.cancel('superseded');
    _request = null;
    _generation++;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _cancelRequest();
    super.dispose();
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }
}
