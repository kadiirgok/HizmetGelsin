import 'package:berbergelsin/features/barber/domain/barber_profile_completion_input.dart';

class BarberProfileCompletionResult {
  final int percentage;
  final List<String> missingItems;

  const BarberProfileCompletionResult({
    required this.percentage,
    required this.missingItems,
  });
}

class BarberProfileCompletion {
  const BarberProfileCompletion._();

  static int calculate(BarberProfileCompletionInput input) {
    return calculateDetailed(input).percentage;
  }

  static BarberProfileCompletionResult calculateDetailed(
    BarberProfileCompletionInput input,
  ) {
    final missingItems = <String>[];
    int completedGroups = 0;
    const totalGroups = 10;

    bool isValidText(String? s) {
      if (s == null) {
        return false;
      }
      final trimmed = s.trim();
      if (trimmed.isEmpty) {
        return false;
      }
      if (trimmed == '-' || trimmed == 'Belirtilmedi' || trimmed == 'Yok') {
        return false;
      }
      return true;
    }

    bool hasValidLocation(double? lat, double? lng) {
      if (lat == null || lng == null) {
        return false;
      }
      if (lat == 0 && lng == 0) {
        return false;
      }
      if (lat.isNaN || lng.isNaN) {
        return false;
      }
      if (lat < -90 || lat > 90) {
        return false;
      }
      if (lng < -180 || lng > 180) {
        return false;
      }
      return true;
    }

    // 1. İşletme adı
    if (isValidText(input.businessName)) {
      completedGroups++;
    } else {
      missingItems.add('İşletme adı ekle');
    }

    // 2. Açıklama
    if (isValidText(input.description)) {
      completedGroups++;
    } else {
      missingItems.add('İşletme açıklaması ekle');
    }

    // 3. Kategori
    if (isValidText(input.category)) {
      completedGroups++;
    } else {
      missingItems.add('Kategori seç');
    }

    // 4. Konum bilgisi
    if (isValidText(input.addressLine)) {
      completedGroups++;
    } else {
      missingItems.add('Konum bilgilerini tamamla');
    }

    // 5. Açık adres
    if (isValidText(input.addressLine)) {
      completedGroups++;
    } else {
      missingItems.add('Konum bilgilerini tamamla');
    }

    // 6. Harita Konumu
    if (hasValidLocation(input.latitude, input.longitude)) {
      completedGroups++;
    } else {
      missingItems.add('Konum bilgilerini tamamla');
    }

    // 7. Logo
    if (input.hasLogo) {
      completedGroups++;
    } else {
      missingItems.add('Logo ekle');
    }

    // 8. Kapak/Vitrin Fotoğrafı
    if (input.hasGalleryOrCoverPhoto) {
      completedGroups++;
    } else {
      missingItems.add('Kapak veya vitrin fotoğrafı ekle');
    }

    // 9. En az bir hizmet
    if (input.hasActiveService) {
      completedGroups++;
    } else {
      missingItems.add('En az bir hizmet ekle');
    }

    // 10. Çalışma Saatleri
    if (input.hasValidWorkingHours) {
      completedGroups++;
    } else {
      missingItems.add('Çalışma saatlerini belirle');
    }

    final percentage = ((completedGroups / totalGroups) * 100).round().clamp(
      0,
      100,
    );
    return BarberProfileCompletionResult(
      percentage: percentage,
      missingItems: missingItems.toSet().toList(),
    );
  }
}
