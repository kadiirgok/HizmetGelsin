import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

class OnboardingStatus {
  OnboardingStatus({
    required this.onboardingCompleted,
    required this.role,
    this.barberStatus,
    this.rejectionReason,
    required this.hasProfileStep,
    required this.uploadedDocuments,
    required this.hasServices,
  });

  final bool onboardingCompleted;
  final String role;
  final String? barberStatus;
  final String? rejectionReason;
  final bool hasProfileStep;
  final List<String> uploadedDocuments;
  final bool hasServices;

  factory OnboardingStatus.fromJson(Map<String, dynamic> json) =>
      OnboardingStatus(
        onboardingCompleted: json['onboardingCompleted'] as bool,
        role: json['role'] as String,
        barberStatus: json['barberStatus'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
        hasProfileStep: json['hasProfileStep'] as bool,
        uploadedDocuments: (json['uploadedDocuments'] as List).cast<String>(),
        hasServices: json['hasServices'] as bool,
      );
}

class OnboardingRepo {
  OnboardingRepo._();
  static final OnboardingRepo instance = OnboardingRepo._();

  final _api = ApiClient.instance;

  Future<OnboardingStatus> status() async => OnboardingStatus.fromJson(
    await _api.get<Map<String, dynamic>>('/api/onboarding/status'),
  );

  Future<void> submitClient({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
  }) => _api.post(
    '/api/onboarding/client',
    data: {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'kvkkAccepted': true,
    },
  );

  Future<void> submitBarberProfile({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String tcKimlikNo,
    required String businessName,
    String? category,
  }) => _api.post(
    '/api/onboarding/barber/profile',
    data: {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'tcKimlikNo': tcKimlikNo,
      'businessName': businessName,
      if (category != null && category.isNotEmpty) 'category': category,
      'kvkkAccepted': true,
    },
  );

  Future<void> uploadDocument({
    required String type, // UstalikBelgesi | EsnafOdasiKaydi
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    final formData = FormData.fromMap({
      'type': type,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    await _api.postMultipart('/api/onboarding/barber/documents', formData);
  }

  Future<void> submitServices({
    required List<({String name, double price})> services,
    required bool acceptsOffers,
  }) => _api.post(
    '/api/onboarding/barber/services',
    data: {
      'services': services
          .map((s) => {'name': s.name, 'price': s.price})
          .toList(),
      'acceptsOffers': acceptsOffers,
    },
  );

  Future<void> complete({
    required bool sharePhone,
    required int serviceRadiusKm,
  }) => _api.post(
    '/api/onboarding/barber/complete',
    data: {
      'sharePhone': sharePhone,
      'serviceRadiusKm': serviceRadiusKm,
      'workingHours': [
        for (var day = 1; day <= 7; day++)
          {'day': day, 'open': '09:00', 'close': '21:00', 'closed': false},
      ],
    },
  );
}
