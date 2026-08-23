/// Mirrors the `facilities` table exactly (0001_init.sql + 0002/0006
/// migrations) — same enum values as the web app's `FacilityType` union.
enum FacilityType {
  badminton,
  pickleball,
  cricket,
  football,
  tennis,
  multiSport,
  other;

  static FacilityType fromDb(String value) {
    switch (value) {
      case 'BADMINTON':
        return FacilityType.badminton;
      case 'PICKLEBALL':
        return FacilityType.pickleball;
      case 'CRICKET':
        return FacilityType.cricket;
      case 'FOOTBALL':
        return FacilityType.football;
      case 'TENNIS':
        return FacilityType.tennis;
      case 'OTHER':
        return FacilityType.other;
      default:
        return FacilityType.multiSport;
    }
  }

  String toDb() {
    switch (this) {
      case FacilityType.badminton:
        return 'BADMINTON';
      case FacilityType.pickleball:
        return 'PICKLEBALL';
      case FacilityType.cricket:
        return 'CRICKET';
      case FacilityType.football:
        return 'FOOTBALL';
      case FacilityType.tennis:
        return 'TENNIS';
      case FacilityType.multiSport:
        return 'MULTI_SPORT';
      case FacilityType.other:
        return 'OTHER';
    }
  }

  String get label {
    switch (this) {
      case FacilityType.badminton:
        return 'Badminton';
      case FacilityType.pickleball:
        return 'Pickleball';
      case FacilityType.cricket:
        return 'Cricket';
      case FacilityType.football:
        return 'Football';
      case FacilityType.tennis:
        return 'Tennis';
      case FacilityType.multiSport:
        return 'Multi-Sport Facility';
      case FacilityType.other:
        return 'Other';
    }
  }
}

enum OnboardingStep {
  facilityDetails,
  sports,
  courts,
  operatingHours,
  pricing,
  completed;

  static OnboardingStep fromDb(String value) {
    switch (value) {
      case 'SPORTS':
        return OnboardingStep.sports;
      case 'COURTS':
        return OnboardingStep.courts;
      case 'OPERATING_HOURS':
        return OnboardingStep.operatingHours;
      case 'PRICING':
        return OnboardingStep.pricing;
      case 'COMPLETED':
        return OnboardingStep.completed;
      default:
        return OnboardingStep.facilityDetails;
    }
  }

  String toDb() {
    switch (this) {
      case OnboardingStep.facilityDetails:
        return 'FACILITY_DETAILS';
      case OnboardingStep.sports:
        return 'SPORTS';
      case OnboardingStep.courts:
        return 'COURTS';
      case OnboardingStep.operatingHours:
        return 'OPERATING_HOURS';
      case OnboardingStep.pricing:
        return 'PRICING';
      case OnboardingStep.completed:
        return 'COMPLETED';
    }
  }
}

class FacilityAddress {
  const FacilityAddress({
    required this.line1,
    required this.area,
    required this.city,
    required this.state,
    required this.country,
    required this.pinCode,
  });

  final String line1;
  final String area;
  final String city;
  final String state;
  final String country;
  final String pinCode;
}

class Facility {
  const Facility({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    this.customType,
    required this.businessEmail,
    required this.businessPhone,
    required this.address,
    this.logoUrl,
    this.description,
    required this.status,
    required this.onboardingStep,
    this.onboardingCompletedAt,
  });

  final String id;
  final String ownerId;
  final String name;
  final FacilityType type;
  final String? customType;
  final String businessEmail;
  final String businessPhone;
  final FacilityAddress address;
  final String? logoUrl;
  final String? description;
  final String status;
  final OnboardingStep onboardingStep;
  final DateTime? onboardingCompletedAt;

  factory Facility.fromJson(Map<String, dynamic> json) {
    return Facility(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      type: FacilityType.fromDb(json['facility_type'] as String? ?? 'MULTI_SPORT'),
      customType: json['custom_facility_type'] as String?,
      businessEmail: json['business_email'] as String? ?? '',
      businessPhone: json['business_phone'] as String? ?? '',
      address: FacilityAddress(
        line1: json['address_line_1'] as String? ?? '',
        area: json['area'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        country: json['country'] as String? ?? 'India',
        pinCode: json['postal_code'] as String? ?? '',
      ),
      logoUrl: json['logo_url'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      onboardingStep: OnboardingStep.fromDb(json['onboarding_step'] as String? ?? 'FACILITY_DETAILS'),
      onboardingCompletedAt: json['onboarding_completed_at'] != null
          ? DateTime.tryParse(json['onboarding_completed_at'] as String)
          : null,
    );
  }
}