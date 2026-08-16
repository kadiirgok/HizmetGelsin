import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.phone,
    required this.role,
    this.firstName,
    this.lastName,
    this.email,
    required this.onboardingCompleted,
    this.barberStatus,
    this.rejectionReason,
    this.avgRating,
    this.ratingCount = 0,
    this.emailVerified = false,
    this.isPhoneVerified = false,
  });

  final String id;
  final String phone;

  /// "Musteri" | "Berber" | "Admin"
  final String role;
  final String? firstName;
  final String? lastName;
  final String? email;
  final bool onboardingCompleted;

  /// "Onboarding" | "PendingApproval" | "Approved" | "Rejected"
  final String? barberStatus;
  final String? rejectionReason;
  final double? avgRating;
  final int ratingCount;
  final bool emailVerified;
  final bool isPhoneVerified;

  bool get isMusteri => role == 'Musteri';
  bool get isBerber => role == 'Berber';
  bool get isAdmin => role == 'Admin';
  bool get isApprovedBerber => isBerber && barberStatus == 'Approved';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    phone: json['phone'] as String,
    role: json['role'] as String,
    firstName: json['firstName'] as String?,
    lastName: json['lastName'] as String?,
    email: json['email'] as String?,
    onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
    barberStatus: json['barberStatus'] as String?,
    rejectionReason: json['rejectionReason'] as String?,
    avgRating: (json['avgRating'] as num?)?.toDouble(),
    ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
    emailVerified: json['emailVerified'] as bool? ?? false,
    isPhoneVerified: json['isPhoneVerified'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'role': role,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'onboardingCompleted': onboardingCompleted,
    'barberStatus': barberStatus,
    'rejectionReason': rejectionReason,
    'avgRating': avgRating,
    'ratingCount': ratingCount,
    'emailVerified': emailVerified,
    'isPhoneVerified': isPhoneVerified,
  };

  @override
  List<Object?> get props => [
    id,
    phone,
    role,
    firstName,
    lastName,
    email,
    onboardingCompleted,
    barberStatus,
    rejectionReason,
    avgRating,
    ratingCount,
    emailVerified,
    isPhoneVerified,
  ];
}
