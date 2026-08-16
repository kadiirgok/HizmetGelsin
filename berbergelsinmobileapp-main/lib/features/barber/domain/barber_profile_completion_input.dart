import 'dart:convert';
import 'package:berbergelsin/features/barber/data/business_working_hours.dart';

class BarberProfileCompletionInput {
  final String? businessName;
  final String? category;
  final String? description;
  final String? addressLine;
  final double? latitude;
  final double? longitude;
  final bool hasLogo;
  final bool hasGalleryOrCoverPhoto;
  final bool hasActiveService;
  final bool hasValidWorkingHours;

  const BarberProfileCompletionInput({
    required this.businessName,
    required this.category,
    required this.description,
    required this.addressLine,
    required this.latitude,
    required this.longitude,
    required this.hasLogo,
    required this.hasGalleryOrCoverPhoto,
    required this.hasActiveService,
    required this.hasValidWorkingHours,
  });

  factory BarberProfileCompletionInput.fromRawData({
    required Map<String, dynamic>? profile,
    required int serviceCount,
    required int photoCount,
    required bool hasLogo,
  }) {
    final Map<String, dynamic> p = profile ?? const {};
    return BarberProfileCompletionInput(
      businessName: p['businessName'] as String?,
      category: p['category'] as String?,
      description: p['description'] as String?,
      addressLine: p['addressLine'] as String?,
      latitude: (p['lat'] as num?)?.toDouble(),
      longitude: (p['lng'] as num?)?.toDouble(),
      hasLogo: hasLogo,
      hasGalleryOrCoverPhoto: photoCount > 0,
      hasActiveService: serviceCount > 0,
      hasValidWorkingHours: validateWorkingHours(p['workingHours']),
    );
  }

  static bool validateWorkingHours(dynamic workingHours) {
    if (workingHours == null) return false;
    List<dynamic>? parsedList;
    try {
      if (workingHours is String) {
        if (workingHours.trim().isNotEmpty) {
          parsedList = jsonDecode(workingHours) as List<dynamic>?;
        }
      } else if (workingHours is List) {
        parsedList = workingHours;
      }
    } catch (_) {}

    if (parsedList == null || parsedList.isEmpty) return false;

    bool hasOpenDay = false;
    for (final item in parsedList) {
      if (item == null) continue;
      try {
        bool closed = false;
        String? openStr;
        String? closeStr;

        if (item is Map) {
          closed = (item['closed'] ?? item['Closed']) as bool? ?? false;
          openStr = (item['open'] ?? item['Open']) as String?;
          closeStr = (item['close'] ?? item['Close']) as String?;
        } else if (item is BusinessWorkingDay) {
          closed = item.closed;
          openStr = item.open;
          closeStr = item.close;
        }

        if (!closed) {
          if (openStr != null &&
              closeStr != null &&
              openStr.contains(':') &&
              closeStr.contains(':')) {
            hasOpenDay = true;
          }
        }
      } catch (_) {}
    }
    return hasOpenDay;
  }
}
