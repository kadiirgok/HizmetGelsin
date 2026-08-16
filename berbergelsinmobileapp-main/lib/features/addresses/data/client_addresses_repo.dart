import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';

class ClientAddress {
  const ClientAddress({
    required this.id,
    required this.label,
    this.placeId,
    this.formattedAddress,
    this.province,
    this.district,
    this.neighborhood,
    this.street,
    this.streetNumber,
    this.postalCode,
    required this.addressLine,
    required this.latitude,
    required this.longitude,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
  });
  final String id, label, addressLine, version;
  final String? placeId,
      formattedAddress,
      province,
      district,
      neighborhood,
      street,
      streetNumber,
      postalCode;
  final double latitude, longitude;
  final bool isDefault;
  final DateTime createdAt, updatedAt;
  factory ClientAddress.fromJson(Map<String, dynamic> j) => ClientAddress(
    id: j['id'] as String,
    label: j['label'] as String,
    placeId: j['placeId'] as String?,
    formattedAddress: j['formattedAddress'] as String?,
    province: j['province'] as String?,
    district: j['district'] as String?,
    neighborhood: j['neighborhood'] as String?,
    street: j['street'] as String?,
    streetNumber: j['streetNumber'] as String?,
    postalCode: j['postalCode'] as String?,
    addressLine: j['addressLine'] as String,
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    isDefault: j['isDefault'] as bool,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    version: j['version'] as String,
  );
  Map<String, dynamic> toPayload() => {
    'label': label,
    'placeId': placeId,
    'formattedAddress': formattedAddress,
    'province': province,
    'district': district,
    'neighborhood': neighborhood,
    'street': street,
    'streetNumber': streetNumber,
    'postalCode': postalCode,
    'addressLine': addressLine,
    'latitude': latitude,
    'longitude': longitude,
    'isDefault': isDefault,
    'version': version,
  };
}

enum ClientAddressError {
  notFound,
  invalid,
  limitReached,
  forbidden,
  conflict,
  defaultConflict,
  rateLimited,
  network,
}

ClientAddressError mapClientAddressError(ApiException e) => switch (e.code) {
  'client_address_not_found' => ClientAddressError.notFound,
  'client_address_invalid' => ClientAddressError.invalid,
  'client_address_limit_reached' => ClientAddressError.limitReached,
  'client_address_forbidden' => ClientAddressError.forbidden,
  'client_address_conflict' => ClientAddressError.conflict,
  'client_address_default_conflict' => ClientAddressError.defaultConflict,
  'client_address_rate_limited' => ClientAddressError.rateLimited,
  _ => ClientAddressError.network,
};
String clientAddressErrorMessage(ClientAddressError e) => switch (e) {
  ClientAddressError.notFound => 'Adres bulunamadı.',
  ClientAddressError.invalid => 'Adres bilgilerini kontrol edin.',
  ClientAddressError.limitReached =>
    'En fazla 10 aktif adres kaydedebilirsiniz.',
  ClientAddressError.forbidden => 'Bu adres için yetkiniz yok.',
  ClientAddressError.conflict =>
    'Adres başka bir yerde güncellendi. Bilgiler yenilendi.',
  ClientAddressError.defaultConflict =>
    'Varsayılan adres değiştirilemedi. Liste yenilendi.',
  ClientAddressError.rateLimited => 'Çok fazla işlem yapıldı. Lütfen bekleyin.',
  ClientAddressError.network => 'Adres işlemi tamamlanamadı. Tekrar deneyin.',
};

abstract interface class ClientAddressesRepository {
  Future<List<ClientAddress>> list();
  Future<ClientAddress> get(String id);
  Future<ClientAddress> create(ClientAddress value);
  Future<ClientAddress> update(ClientAddress value);
  Future<void> delete(String id);
  Future<ClientAddress> setDefault(String id);
}

class ClientAddressesRepo implements ClientAddressesRepository {
  ClientAddressesRepo._();
  static final instance = ClientAddressesRepo._();
  final _api = ApiClient.instance;
  @override
  Future<List<ClientAddress>> list() async {
    final d = await _api.get<List<dynamic>>('/api/client/addresses');
    final seen = <String>{};
    return d
        .map((e) => ClientAddress.fromJson(e as Map<String, dynamic>))
        .where((e) => seen.add(e.id))
        .toList();
  }

  @override
  Future<ClientAddress> get(String id) async => ClientAddress.fromJson(
    await _api.get<Map<String, dynamic>>('/api/client/addresses/$id'),
  );
  @override
  Future<ClientAddress> create(ClientAddress v) async => ClientAddress.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/api/client/addresses',
      data: v.toPayload()..remove('version'),
    ),
  );
  @override
  Future<ClientAddress> update(ClientAddress v) async => ClientAddress.fromJson(
    await _api.put<Map<String, dynamic>>(
      '/api/client/addresses/${v.id}',
      data: v.toPayload(),
    ),
  );
  @override
  Future<void> delete(String id) => _api.delete('/api/client/addresses/$id');
  @override
  Future<ClientAddress> setDefault(String id) async => ClientAddress.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/api/client/addresses/$id/set-default',
    ),
  );
}

/// Keeps the customer's active saved address consistent between customer
/// surfaces. It stores no token or customer identifier and is cleared at every
/// customer session boundary.
class CustomerAddressSelectionStore extends ChangeNotifier {
  CustomerAddressSelectionStore._();

  static final instance = CustomerAddressSelectionStore._();

  ClientAddress? _selectedAddress;
  ClientAddress? get selectedAddress => _selectedAddress;
  String? get selectedAddressId => _selectedAddress?.id;

  ClientAddress? resolve(List<ClientAddress> addresses) {
    final selectedId = _selectedAddress?.id;
    final resolved = selectedId == null
        ? null
        : addresses.where((address) => address.id == selectedId).firstOrNull;
    _selectedAddress =
        resolved ??
        addresses.where((address) => address.isDefault).firstOrNull ??
        addresses.firstOrNull;
    return _selectedAddress;
  }

  void select(ClientAddress? address) {
    if (_selectedAddress?.id == address?.id) {
      _selectedAddress = address;
      return;
    }
    _selectedAddress = address;
    notifyListeners();
  }

  void clearSession() {
    if (_selectedAddress == null) return;
    _selectedAddress = null;
    notifyListeners();
  }
}
