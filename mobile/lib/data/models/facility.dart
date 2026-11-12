import 'facility_image.dart';

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

/// Indoor or outdoor: the two kinds of venue (`facilities.venue_type`).
enum VenueType {
  indoor,
  outdoor;

  static VenueType? fromDb(String? value) => switch (value) {
        'INDOOR' => VenueType.indoor,
        'OUTDOOR' => VenueType.outdoor,
        _ => null,
      };

  String toDb() => this == VenueType.indoor ? 'INDOOR' : 'OUTDOOR';
  String get label => this == VenueType.indoor ? 'Indoor' : 'Outdoor';
  String get hint => this == VenueType.indoor ? 'Under a roof: halls, indoor courts' : 'In the open: turfs, open courts';
}

/// The five things a venue says it offers; each is simply on or off.
class FacilityAmenities {
  const FacilityAmenities({this.parking = false, this.changingRooms = false, this.toilets = false, this.cafeteria = false, this.equipmentRental = false});

  final bool parking;
  final bool changingRooms;
  final bool toilets;
  final bool cafeteria;
  final bool equipmentRental;

  factory FacilityAmenities.fromJson(Map<String, dynamic> json) => FacilityAmenities(
        parking: json['has_parking'] == true,
        changingRooms: json['has_changing_rooms'] == true,
        toilets: json['has_toilets'] == true,
        cafeteria: json['has_cafeteria'] == true,
        equipmentRental: json['has_equipment_rental'] == true,
      );

  Map<String, dynamic> toDb() => {
        'has_parking': parking,
        'has_changing_rooms': changingRooms,
        'has_toilets': toilets,
        'has_cafeteria': cafeteria,
        'has_equipment_rental': equipmentRental,
      };

  FacilityAmenities copyWith({bool? parking, bool? changingRooms, bool? toilets, bool? cafeteria, bool? equipmentRental}) => FacilityAmenities(
        parking: parking ?? this.parking,
        changingRooms: changingRooms ?? this.changingRooms,
        toilets: toilets ?? this.toilets,
        cafeteria: cafeteria ?? this.cafeteria,
        equipmentRental: equipmentRental ?? this.equipmentRental,
      );

  /// The labels of the ones that are on, in a fixed order.
  List<String> get labels => [
        if (parking) 'Free Parking',
        if (changingRooms) 'Changing Rooms',
        if (toilets) 'Toilets / Rest Room',
        if (cafeteria) 'Cafeteria',
        if (equipmentRental) 'Equipment Rental',
      ];
}

/// Owned or leased premises (`facilities.ownership_type`).
enum OwnershipType {
  owned,
  leased;

  static OwnershipType fromDb(String? value) => value == 'LEASED' ? OwnershipType.leased : OwnershipType.owned;
  String toDb() => this == OwnershipType.leased ? 'LEASED' : 'OWNED';
  String get label => this == OwnershipType.leased ? 'Leased' : 'Owned';
}

/// The five switches under "Facility Policies" (boolean columns on `facilities`).
class FacilityPolicies {
  const FacilityPolicies({
    this.allowOnlineBooking = true,
    this.allowWalkIn = true,
    this.advancePaymentRequired = false,
    this.allowCancellations = true,
    this.requirePlayerDetails = true,
  });

  final bool allowOnlineBooking;
  final bool allowWalkIn;
  final bool advancePaymentRequired;
  final bool allowCancellations;
  final bool requirePlayerDetails;

  factory FacilityPolicies.fromJson(Map<String, dynamic> json) => FacilityPolicies(
        allowOnlineBooking: json['allow_online_booking'] as bool? ?? true,
        allowWalkIn: json['allow_walk_in_booking'] as bool? ?? true,
        advancePaymentRequired: json['advance_payment_required'] as bool? ?? false,
        allowCancellations: json['allow_cancellations'] as bool? ?? true,
        requirePlayerDetails: json['require_player_details'] as bool? ?? true,
      );

  Map<String, dynamic> toDb() => {
        'allow_online_booking': allowOnlineBooking,
        'allow_walk_in_booking': allowWalkIn,
        'advance_payment_required': advancePaymentRequired,
        'allow_cancellations': allowCancellations,
        'require_player_details': requirePlayerDetails,
      };

  FacilityPolicies copyWith({bool? allowOnlineBooking, bool? allowWalkIn, bool? advancePaymentRequired, bool? allowCancellations, bool? requirePlayerDetails}) => FacilityPolicies(
        allowOnlineBooking: allowOnlineBooking ?? this.allowOnlineBooking,
        allowWalkIn: allowWalkIn ?? this.allowWalkIn,
        advancePaymentRequired: advancePaymentRequired ?? this.advancePaymentRequired,
        allowCancellations: allowCancellations ?? this.allowCancellations,
        requirePlayerDetails: requirePlayerDetails ?? this.requirePlayerDetails,
      );
}

/// Who to reach about bookings and operations.
class FacilityContactPerson {
  const FacilityContactPerson({required this.name, required this.role, this.alternatePhone});

  final String name;
  final String role;
  final String? alternatePhone;
}

/// One of the 12 amenities a venue can offer (`facilities.amenity_keys` holds the keys).
class AmenityOption {
  const AmenityOption(this.key, this.label);
  final String key;
  final String label;
}

const List<AmenityOption> kFacilityAmenities = [
  AmenityOption('car_parking', 'Car Parking'),
  AmenityOption('two_wheeler_parking', 'Two-Wheeler Parking'),
  AmenityOption('restroom', 'Restroom'),
  AmenityOption('changing_room', 'Changing Room'),
  AmenityOption('shower', 'Shower'),
  AmenityOption('drinking_water', 'Drinking Water'),
  AmenityOption('seating_area', 'Seating Area'),
  AmenityOption('cafeteria', 'Cafeteria / Food'),
  AmenityOption('wifi', 'Wi-Fi'),
  AmenityOption('lockers', 'Lockers'),
  AmenityOption('equipment_rental', 'Equipment Rental'),
  AmenityOption('first_aid', 'First Aid'),
];

const int kMaxCustomAmenities = 10;
const List<String> kContactRoles = ['Facility Owner', 'Manager', 'Receptionist', 'Coach', 'Other'];

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
    this.locationVerification = VerificationStatus.pending,
    this.locationVerificationNote,
    this.venueType,
    this.amenities = const FacilityAmenities(),
    this.description,
    this.ownershipType = OwnershipType.owned,
    this.whatsappNumber,
    this.contactPerson,
    this.policies = const FacilityPolicies(),
    this.amenityKeys = const [],
    this.customAmenities = const [],
    this.allowBookingsOutsideHours = false,
    this.breakStart,
    this.breakEnd,
    this.sportWiseHours = false,
    required this.status,
    required this.onboardingStep,
    this.onboardingCompletedAt,
    this.pricingMode = 'BY_SPORT',
    this.differentWeekendPricing = true,
    this.memberPricingEnabled = false,
    this.coachingPricingEnabled = false,
    this.setupReviewStatus,
    this.setupReviewNote,
    this.membershipAccessDays = const [0, 1, 2, 3, 4, 5, 6],
  });

  final String id;
  final String ownerId;
  final String name;

  /// A human-readable identifier (`facilities.slug`) stored for the
  /// facility, but not currently wired into any public route — the actual
  /// public booking/join pages (`/book/:id`, `/join/:id`) are keyed by
  /// [id], since their backing RPCs take a `uuid` param. Don't build a
  /// shareable link from this field.
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

  /// What GameAll's admin decided about the link (it starts as pending, and goes back to pending when the link changes).
  final VerificationStatus locationVerification;
  final String? locationVerificationNote;

  /// Indoor or outdoor; null for a facility set up before the owner was asked.
  final VenueType? venueType;
  final FacilityAmenities amenities;
  final String? description;
  final OwnershipType ownershipType;
  final String? whatsappNumber;
  final FacilityContactPerson? contactPerson;
  final FacilityPolicies policies;

  /// The amenities on offer (keys from [kFacilityAmenities]) and any the owner typed in.
  final List<String> amenityKeys;
  final List<String> customAmenities;

  /// Owner / manager / staff may create bookings outside the working hours.
  final bool allowBookingsOutsideHours;

  /// A fixed daily break ("HH:MM"), both or neither.
  final String? breakStart;
  final String? breakEnd;

  /// Each sport has its own hours (stored as per-court schedules).
  final bool sportWiseHours;
  final String status;
  final OnboardingStep onboardingStep;
  final DateTime? onboardingCompletedAt;

  /// The Pricing step's settings (migration 0199).
  final String pricingMode; // BY_SPORT | BY_COURT
  final bool differentWeekendPricing;
  final bool memberPricingEnabled;
  final bool coachingPricingEnabled;

  /// GameAll's verdict on the finished setup (migration 0200): NOT_SUBMITTED | PENDING | APPROVED | REJECTED. Null when the database does
  /// not have the column yet — nothing is enforced then, so an older database never locks anyone out.
  final String? setupReviewStatus;
  final String? setupReviewNote;

  /// True while the owner has finished setup but GameAll has not approved it: the app shows only the review screen.
  bool get awaitingApproval => setupReviewStatus == 'PENDING' || setupReviewStatus == 'REJECTED';

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
      locationVerification: VerificationStatus.fromDb(json['location_verification_status'] as String?),
      locationVerificationNote: json['location_verification_note'] as String?,
      venueType: VenueType.fromDb(json['venue_type'] as String?),
      amenities: FacilityAmenities.fromJson(json),
      description: json['description'] as String?,
      ownershipType: OwnershipType.fromDb(json['ownership_type'] as String?),
      whatsappNumber: json['whatsapp_number'] as String?,
      contactPerson: (json['contact_person_name'] as String?)?.isNotEmpty == true
          ? FacilityContactPerson(
              name: json['contact_person_name'] as String,
              role: json['contact_person_role'] as String? ?? '',
              alternatePhone: json['contact_person_alt_phone'] as String?,
            )
          : null,
      policies: FacilityPolicies.fromJson(json),
      amenityKeys: ((json['amenity_keys'] as List<dynamic>?) ?? const []).map((e) => e as String).toList(),
      customAmenities: ((json['custom_amenities'] as List<dynamic>?) ?? const []).map((e) => e as String).toList(),
      allowBookingsOutsideHours: json['allow_bookings_outside_hours'] as bool? ?? false,
      breakStart: (json['operating_break_start'] as String?)?.substring(0, 5),
      breakEnd: (json['operating_break_end'] as String?)?.substring(0, 5),
      sportWiseHours: json['sport_wise_hours'] as bool? ?? false,
      pricingMode: json['pricing_mode'] as String? ?? 'BY_SPORT',
      differentWeekendPricing: json['different_weekend_pricing'] as bool? ?? true,
      memberPricingEnabled: json['member_pricing_enabled'] as bool? ?? false,
      coachingPricingEnabled: json['coaching_pricing_enabled'] as bool? ?? false,
      setupReviewStatus: json['setup_review_status'] as String?,
      setupReviewNote: json['setup_review_note'] as String?,
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