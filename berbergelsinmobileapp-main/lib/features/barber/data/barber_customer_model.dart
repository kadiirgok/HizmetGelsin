class BarberCustomerModel {
  BarberCustomerModel({
    required this.customerId,
    required this.displayName,
    required this.phone,
    required this.firstVisit,
    required this.lastVisit,
    required this.completedJobCount,
    required this.totalSpent,
    required this.averageTicket,
    required this.preferredServices,
    required this.recentJobs,
  });

  final String customerId;
  final String displayName;
  final String? phone;
  final DateTime firstVisit;
  final DateTime lastVisit;
  final int completedJobCount;
  final double totalSpent;
  final double averageTicket;
  final List<String> preferredServices;
  final List<BarberCustomerRecentJobModel> recentJobs;

  bool get isActive => DateTime.now().difference(lastVisit).inDays <= 30;
  bool get isVip => totalSpent >= 2000 || completedJobCount >= 5;
  String get statusLabel => isVip
      ? 'VIP'
      : isActive
      ? 'Aktif'
      : 'Yeni';

  String get preferredServicesText => preferredServices.join(', ');

  factory BarberCustomerModel.fromJson(Map<String, dynamic> json) {
    final displayName = (json['displayName'] as String?)?.trim();
    final phone = (json['phone'] as String?)?.trim();
    return BarberCustomerModel(
      customerId: json['customerId'] as String? ?? '',
      displayName: displayName == null || displayName.isEmpty
          ? 'Müşteri'
          : displayName,
      phone: phone == null || phone.isEmpty ? null : phone,
      firstVisit: DateTime.parse(json['firstVisit'] as String).toLocal(),
      lastVisit: DateTime.parse(json['lastVisit'] as String).toLocal(),
      completedJobCount: (json['completedJobCount'] as num?)?.toInt() ?? 0,
      totalSpent: (json['totalSpent'] as num?)?.toDouble() ?? 0,
      averageTicket: (json['averageTicket'] as num?)?.toDouble() ?? 0,
      preferredServices: _stringList(json['preferredServices']),
      recentJobs: (json['recentJobs'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => BarberCustomerRecentJobModel.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class BarberCustomerRecentJobModel {
  BarberCustomerRecentJobModel({
    required this.requestId,
    required this.visitDate,
    required this.totalPrice,
    required this.services,
  });

  final String requestId;
  final DateTime visitDate;
  final double totalPrice;
  final List<String> services;

  factory BarberCustomerRecentJobModel.fromJson(Map<String, dynamic> json) =>
      BarberCustomerRecentJobModel(
        requestId: json['requestId'] as String? ?? '',
        visitDate: DateTime.parse(json['visitDate'] as String).toLocal(),
        totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0,
        services: _stringList(json['services']),
      );
}

List<String> _stringList(Object? value) => (value as List? ?? const [])
    .whereType<String>()
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

class CustomerPage {
  const CustomerPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
  });
  final List<BarberCustomerModel> items;
  final int page, pageSize, totalCount, totalPages;

  factory CustomerPage.fromJson(Map<String, dynamic> json) => CustomerPage(
        items: (json['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) =>
                BarberCustomerModel.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        page: json['page'] as int? ?? 1,
        pageSize: json['pageSize'] as int? ?? 50,
        totalCount: json['totalCount'] as int? ?? 0,
        totalPages: json['totalPages'] as int? ?? 0,
      );
}
