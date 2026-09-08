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

/// The redesigned mobile onboarding flow: Facility Details → Sports & Courts
/// (one merged step) → Pricing → Operating Hours → done.
///
/// The database `onboarding_step` enum still carries the pre-redesign values
/// (`SPORTS`, `COURTS`, `PRICING`, `OPERATING_HOURS`, …). [fromDb] folds both
/// `SPORTS` and `COURTS` onto [sportsCourts]; that merged step writes
/// `COURTS` back via [toDb] when it completes, so no enum migration is
/// needed and the web client keeps working on the same values.
enum OnboardingStep {
  facilityDetails,
  sportsCourts,
  pricing,
  operatingHours,
  payments,
  completed;

  static OnboardingStep fromDb(String value) {
    switch (value) {
      case 'SPORTS':
      case 'COURTS':
      case 'SPORTS_COURTS':
        return OnboardingStep.sportsCourts;
      case 'PRICING':
        return OnboardingStep.pricing;
      case 'OPERATING_HOURS':
        return OnboardingStep.operatingHours;
      case 'PAYMENTS':
        return OnboardingStep.payments;
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
      case OnboardingStep.sportsCourts:
        return 'COURTS';
      case OnboardingStep.pricing:
        return 'PRICING';
      case OnboardingStep.operatingHours:
        return 'OPERATING_HOURS';
      case OnboardingStep.payments:
        return 'PAYMENTS';
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
    this.slug,
    required this.type,
    this.customType,
    required this.businessEmail,
    required this.businessPhone,
    required this.address,
    this.logoUrl,
    this.locationUrl,
    this.description,
    required this.status,
    required this.onboardingStep,
    this.onboardingCompletedAt,
    this.membershipAccessDays = const [0, 1, 2, 3, 4, 5, 6],
  });

  final String id;
  final String ownerId;
  final String name;

  /// URL slug for the public booking page — `facilities.slug`.
  final String? slug;
  final FacilityType type;
  final String? customType;
  final String businessEmail;
  final String businessPhone;
  final FacilityAddress address;
  final String? logoUrl;

  /// A Google Maps location link the owner pastes on the Facility Details
  /// step — `facilities.location_url`. Free-form; not parsed into lat/lng.
  final String? locationUrl;
  final String? description;
  final String status;
  final OnboardingStep onboardingStep;
  final DateTime? onboardingCompletedAt;

  /// Which weekdays memberships grant court access (0 = Sun .. 6 = Sat) —
  /// `facilities.membership_access_days` (migration 0029). Pre-fills every new
  /// membership's time slot. Defaults to all seven days.
  final List<int> membershipAccessDays;

  factory Facility.fromJson(Map<String, dynamic> json) {
    return Facility(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String?,
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
      locationUrl: json['location_url'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      onboardingStep: OnboardingStep.fromDb(json['onboarding_step'] as String? ?? 'FACILITY_DETAILS'),
      onboardingCompletedAt: json['onboarding_completed_at'] != null
          ? DateTime.tryParse(json['onboarding_completed_at'] as String)
          : null,
      membershipAccessDays: (json['membership_access_days'] as List<dynamic>?)
              ?.map((d) => (d as num).toInt())
              .toList() ??
          const [0, 1, 2, 3, 4, 5, 6],
    );
  }
}