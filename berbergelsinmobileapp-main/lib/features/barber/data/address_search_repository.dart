import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

class AddressSuggestion {
  const AddressSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    required this.displayText,
  });
  final String placeId;
  final String primaryText;
  final String secondaryText;
  final String displayText;

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) =>
      AddressSuggestion(
        placeId: json['placeId'] as String? ?? '',
        primaryText: json['primaryText'] as String? ?? '',
        secondaryText: json['secondaryText'] as String? ?? '',
        displayText: json['displayText'] as String? ?? '',
      );
}

class ResolvedAddress {
  const ResolvedAddress({
    required this.placeId,
    required this.latitude,
    required this.longitude,
    this.formattedAddress,
    this.province,
    this.district,
    this.neighborhood,
    this.street,
    this.streetNumber,
    this.postalCode,
    this.countryCode,
  });
  final String placeId;
  final String? formattedAddress,
      province,
      district,
      neighborhood,
      street,
      streetNumber,
      postalCode,
      countryCode;
  final double latitude, longitude;

  factory ResolvedAddress.fromJson(Map<String, dynamic> json) =>
      ResolvedAddress(
        placeId: json['placeId'] as String? ?? '',
        formattedAddress: json['formattedAddress'] as String?,
        province: json['province'] as String?,
        district: json['district'] as String?,
        neighborhood: json['neighborhood'] as String?,
        street: json['street'] as String?,
        streetNumber: json['streetNumber'] as String?,
        postalCode: json['postalCode'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        countryCode: json['countryCode'] as String?,
      );
}

abstract interface class AddressSearchRepository {
  Future<List<AddressSuggestion>> suggestions(
    String query,
    String sessionToken,
    CancelToken cancelToken,
  );
  Future<ResolvedAddress> details(
    String placeId,
    String sessionToken,
    CancelToken cancelToken,
  );
}

class BackendAddressSearchRepository implements AddressSearchRepository {
  BackendAddressSearchRepository({ApiClient? client})
    : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  @override
  Future<List<AddressSuggestion>> suggestions(
    String query,
    String sessionToken,
    CancelToken cancelToken,
  ) async {
    final data = await _client.get<List<dynamic>>(
      '/api/locations/address-suggestions',
      query: {'q': query, 'sessionToken': sessionToken},
      cancelToken: cancelToken,
    );
    return data
        .whereType<Map>()
        .map((item) => AddressSuggestion.fromJson(item.cast<String, dynamic>()))
        .where((item) => item.placeId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<ResolvedAddress> details(
    String placeId,
    String sessionToken,
    CancelToken cancelToken,
  ) async {
    final data = await _client.get<Map<String, dynamic>>(
      '/api/locations/places/${Uri.encodeComponent(placeId)}',
      query: {'sessionToken': sessionToken},
      cancelToken: cancelToken,
    );
    return ResolvedAddress.fromJson(data);
  }
}
