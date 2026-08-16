import 'package:flutter/foundation.dart';

typedef SmokeCustomer = ({String id, String displayName});
typedef SmokeAddress = ({
  String id,
  String label,
  String shortAddress,
  bool isDefault,
});
typedef SmokeCategory = ({String id, String name});
typedef SmokeBusiness = ({
  String id,
  String name,
  String category,
  double rating,
  int reviewCount,
  int minimumPrice,
  bool isOpen,
});
typedef SmokeService = ({String id, String name, int price, int minutes});
typedef SmokeRequest = ({String id, String status, String summary});
typedef SmokeOffer = ({
  String id,
  String businessName,
  int price,
  String status,
});
typedef SmokeAppointment = ({
  String id,
  String businessName,
  String timeLabel,
  String status,
});
typedef SmokeRating = ({
  String id,
  String businessName,
  int score,
  String comment,
  String moderation,
});
typedef SmokeNotification = ({
  String id,
  String title,
  String body,
  bool isRead,
});

/// The complete, deterministic customer-smoke dependency graph.
///
/// It owns no HTTP client, token store, push provider, SignalR client or
/// persistence adapter. All mutations remain in memory until the process ends.
class CustomerSmokeDependencies {
  CustomerSmokeDependencies._({required this.repository});

  factory CustomerSmokeDependencies.isolated() => CustomerSmokeDependencies._(
    repository: InMemoryCustomerSmokeRepository(),
  );

  final InMemoryCustomerSmokeRepository repository;

  bool get hasHttpClient => false;
  bool get hasSignalRClient => false;
  bool get hasPushTokenProvider => false;
  bool get hasPersistentStorage => false;
}

class InMemoryCustomerSmokeRepository extends ChangeNotifier {
  final SmokeCustomer customer = (
    id: 'smoke-customer-001',
    displayName: 'Smoke Müşteri',
  );

  final List<SmokeAddress> addresses = const [
    (
      id: 'smoke-address-home',
      label: 'Ev',
      shortAddress: 'Beşiktaş, İstanbul',
      isDefault: true,
    ),
    (
      id: 'smoke-address-work',
      label: 'İş',
      shortAddress: 'Şişli, İstanbul',
      isDefault: false,
    ),
  ];

  final List<SmokeCategory> categories = const [
    (id: 'smoke-category-hair', name: 'Saç Bakımı'),
    (id: 'smoke-category-beard', name: 'Sakal Bakımı'),
    (id: 'smoke-category-skin', name: 'Cilt Bakımı'),
  ];

  final List<SmokeBusiness> businesses = const [
    (
      id: 'smoke-business-atelier',
      name: 'Atölye Erkek Bakım Stüdyosu',
      category: 'Berber ve kişisel bakım',
      rating: 4.8,
      reviewCount: 126,
      minimumPrice: 350,
      isOpen: true,
    ),
    (
      id: 'smoke-business-neighborhood',
      name: 'Mahalle Saç Tasarım',
      category: 'Saç tasarımı',
      rating: 4.6,
      reviewCount: 84,
      minimumPrice: 300,
      isOpen: false,
    ),
  ];

  final List<SmokeService> services = const [
    (id: 'smoke-service-cut', name: 'Saç Kesimi', price: 450, minutes: 40),
    (id: 'smoke-service-beard', name: 'Sakal Bakımı', price: 300, minutes: 25),
  ];

  final SmokeRequest request = (
    id: 'smoke-request-001',
    status: 'Teklif bekleniyor',
    summary: 'Saç Kesimi · Ev · Bugün 18.30',
  );

  final List<SmokeOffer> offers = const [
    (
      id: 'smoke-offer-001',
      businessName: 'Atölye Erkek Bakım Stüdyosu',
      price: 450,
      status: 'Aktif',
    ),
    (
      id: 'smoke-offer-002',
      businessName: 'Mahalle Saç Tasarım',
      price: 400,
      status: 'Süresi doldu',
    ),
  ];

  final List<SmokeAppointment> appointments = const [
    (
      id: 'smoke-appointment-001',
      businessName: 'Atölye Erkek Bakım Stüdyosu',
      timeLabel: 'Bugün · 18.30',
      status: 'Onaylandı',
    ),
  ];

  final List<SmokeRating> ratings = const [
    (
      id: 'smoke-rating-001',
      businessName: 'Atölye Erkek Bakım Stüdyosu',
      score: 5,
      comment: 'Hizmet zamanında ve özenliydi.',
      moderation: 'Yayında',
    ),
  ];

  final List<SmokeNotification> notifications = [
    (
      id: 'smoke-notification-001',
      title: 'Yeni teklifiniz var',
      body: 'Talebiniz için yeni bir fiyat teklifi geldi.',
      isRead: false,
    ),
    (
      id: 'smoke-notification-002',
      title: 'Randevunuz onaylandı',
      body: 'Randevu ayrıntılarını görüntüleyebilirsiniz.',
      isRead: true,
    ),
  ];

  String selectedAddressId = 'smoke-address-home';
  String? manualAddress;
  String selectedCategoryId = 'smoke-category-hair';
  String selectedServiceId = 'smoke-service-cut';
  final Set<String> favoriteBusinessIds = {'smoke-business-atelier'};
  int networkAttemptCount = 0;
  int signalRAttemptCount = 0;
  int pushRegistrationAttemptCount = 0;

  void selectAddress(String id) {
    assert(addresses.any((address) => address.id == id));
    selectedAddressId = id;
    manualAddress = null;
    notifyListeners();
  }

  void useManualAddress(String value) {
    manualAddress = value.trim();
    notifyListeners();
  }

  void selectCategory(String id) {
    assert(categories.any((category) => category.id == id));
    selectedCategoryId = id;
    notifyListeners();
  }

  void selectService(String id) {
    assert(services.any((service) => service.id == id));
    selectedServiceId = id;
    notifyListeners();
  }

  void toggleFavorite(String id) {
    favoriteBusinessIds.contains(id)
        ? favoriteBusinessIds.remove(id)
        : favoriteBusinessIds.add(id);
    notifyListeners();
  }

  void markAllNotificationsRead() {
    for (var index = 0; index < notifications.length; index++) {
      final item = notifications[index];
      notifications[index] = (
        id: item.id,
        title: item.title,
        body: item.body,
        isRead: true,
      );
    }
    notifyListeners();
  }
}
