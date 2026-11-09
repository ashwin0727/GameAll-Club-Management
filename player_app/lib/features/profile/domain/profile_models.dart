import '../../auth/domain/player_profile.dart';

/// The choices for "Gender" (the value is what the database stores).
enum Gender {
  male('MALE', 'Male'),
  female('FEMALE', 'Female'),
  other('OTHER', 'Other'),
  private('PREFER_NOT_TO_SAY', 'Prefer not to say');

  const Gender(this.wire, this.label);
  final String wire;
  final String label;

  static Gender? fromWire(String? v) {
    for (final g in Gender.values) {
      if (g.wire == v) return g;
    }
    return null;
  }
}

/// A choice stored by its [wire] value and shown as its [label] (playing level, ID proof type).
class WireOption {
  const WireOption(this.wire, this.label);
  final String wire;
  final String label;
}

const bloodGroups = <String>['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
const tshirtSizes = <String>['XS', 'S', 'M', 'L', 'XL', 'XXL'];
const playingLevels = <WireOption>[
  WireOption('BEGINNER', 'Beginner'),
  WireOption('INTERMEDIATE', 'Intermediate'),
  WireOption('ADVANCED', 'Advanced'),
  WireOption('PROFESSIONAL', 'Professional'),
];
const idDocTypes = <WireOption>[
  WireOption('AADHAAR', 'Aadhaar'),
  WireOption('PASSPORT', 'Passport'),
  WireOption('DRIVING_LICENCE', 'Driving licence'),
  WireOption('VOTER_ID', 'Voter ID'),
  WireOption('SCHOOL_ID', 'School / college ID'),
  WireOption('OTHER', 'Other'),
];
const indianStates = <String>[
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh',
  'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha',
  'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
  'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Jammu and Kashmir', 'Ladakh',
  'Lakshadweep', 'Puducherry',
];

/// A sport a player can mark as preferred (GameAll's own list).
class SportOption {
  const SportOption(this.key, this.name);
  final String key;
  final String name;
}

/// Everything on the My Profile screen about the person: the sign-in details plus the Player ID, date of birth, gender, city and photo.
class ProfileDetails {
  const ProfileDetails({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    this.playerCode,
    this.dob,
    this.gender,
    this.city,
    this.avatarUrl,
    this.bloodGroup,
    this.tshirtSize,
    this.preferredSports = const [],
    this.playingLevel,
    this.about,
    this.altPhone,
    this.emergencyName,
    this.emergencyRelation,
    this.emergencyPhone,
    this.addressLine1,
    this.addressLine2,
    this.state,
    this.pincode,
    this.idDocType,
    this.idDocPath,
    this.idDocName,
    this.isFallback = false,
  });

  factory ProfileDetails.fromJson(Map<String, dynamic> json) {
    String? clean(Object? v) {
      final s = (v as String?)?.trim();
      return s == null || s.isEmpty ? null : s;
    }

    return ProfileDetails(
      id: json['id'] as String,
      fullName: (json['fullName'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      email: clean(json['email']),
      playerCode: clean(json['playerCode']),
      dob: json['dob'] is String ? DateTime.tryParse(json['dob'] as String) : null,
      gender: Gender.fromWire(json['gender'] as String?),
      city: clean(json['city']),
      avatarUrl: clean(json['avatarUrl']),
      bloodGroup: clean(json['bloodGroup']),
      tshirtSize: clean(json['tshirtSize']),
      preferredSports: [
        for (final s in (json['preferredSports'] as List<dynamic>? ?? const []))
          if (s is String) s,
      ],
      playingLevel: clean(json['playingLevel']),
      about: clean(json['about']),
      altPhone: clean(json['altPhone']),
      emergencyName: clean(json['emergencyName']),
      emergencyRelation: clean(json['emergencyRelation']),
      emergencyPhone: clean(json['emergencyPhone']),
      addressLine1: clean(json['addressLine1']),
      addressLine2: clean(json['addressLine2']),
      state: clean(json['state']),
      pincode: clean(json['pincode']),
      idDocType: clean(json['idDocType']),
      idDocPath: clean(json['idDocPath']),
      idDocName: clean(json['idDocName']),
    );
  }

  /// The basic profile (before migration 0187 is applied there is nothing more to show).
  factory ProfileDetails.fromBasic(PlayerProfile p) => ProfileDetails(
    id: p.id,
    fullName: p.fullName,
    phone: p.phone,
    email: p.email,
    // a stand-in ID from the account id, so the screen is never empty; the real one comes with the migration
    playerCode: 'GA${_digits(p.id)}',
    isFallback: true,
  );

  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final String? playerCode;
  final DateTime? dob;
  final Gender? gender;
  final String? city;
  final String? avatarUrl;
  final String? bloodGroup;
  final String? tshirtSize;

  /// sports.key values.
  final List<String> preferredSports;
  final String? playingLevel;
  final String? about;
  final String? altPhone;
  final String? emergencyName;
  final String? emergencyRelation;
  final String? emergencyPhone;
  final String? addressLine1;
  final String? addressLine2;
  final String? state;
  final String? pincode;
  final String? idDocType;

  /// The private file's address in the player-documents bucket.
  final String? idDocPath;
  final String? idDocName;

  /// True for the stand-in built from the sign-in alone (the real profile could not be read): its blanks are NOT the player's data.
  final bool isFallback;

  String get initials => PlayerProfile(id: id, fullName: fullName, phone: phone).initials;

  static String _digits(String id) {
    final d = id.replaceAll(RegExp(r'[^0-9]'), '');
    return (d.length >= 8 ? d.substring(0, 8) : d.padRight(8, '0'));
  }

  PlayerProfile toBasic() =>
      PlayerProfile(id: id, fullName: fullName, phone: phone, email: email);
}

/// The numbers under the name. [tournaments] is null: tournaments run in the separate GameAll Tournaments app.
class ProfileStats {
  const ProfileStats({
    this.bookings = 0,
    this.memberships = 0,
    this.coaching = 0,
    this.tournaments,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) => ProfileStats(
    bookings: (json['bookings'] as num?)?.toInt() ?? 0,
    memberships: (json['memberships'] as num?)?.toInt() ?? 0,
    coaching: (json['coaching'] as num?)?.toInt() ?? 0,
    tournaments: (json['tournaments'] as num?)?.toInt(),
  );

  final int bookings;
  final int memberships;
  final int coaching;
  final int? tournaments;
}

/// One line of Payment & Billing: a payment, or a refund.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.isRefund,
    required this.source,
    required this.sourceId,
    required this.amountInr,
    required this.status,
    required this.at,
    this.method,
    this.venueName = '',
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
    id: (json['id'] as String?) ?? '',
    isRefund: json['kind'] == 'refund',
    source: (json['source'] as String?) ?? 'booking',
    sourceId: (json['sourceId'] as String?) ?? '',
    amountInr: (json['amountInr'] as num?)?.toInt() ?? 0,
    status: ((json['status'] as String?) ?? 'PENDING').toUpperCase(),
    at: DateTime.tryParse((json['at'] as String?) ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    method: json['method'] as String?,
    venueName: (json['venueName'] as String?) ?? '',
  );

  final String id;
  final bool isRefund;

  /// 'booking' | 'membership' | 'coaching'
  final String source;
  final String sourceId;
  final int amountInr;

  /// PAID | PENDING | FAILED | REFUNDED for payments; the refund's own status (REQUESTED, PROCESSED ...) for refunds.
  final String status;
  final DateTime at;
  final String? method;
  final String venueName;

  bool get isPaid => !isRefund && status == 'PAID';

  String get sourceLabel => switch (source) {
    'membership' => 'Membership',
    'coaching' => 'Coaching',
    _ => 'Court booking',
  };

  /// "Paid", "Pending", "Failed", "Refunded"; a refund says how far it got.
  String get statusLabel {
    if (isRefund) {
      return switch (status) {
        'PROCESSED' => 'Refunded',
        'FAILED' => 'Refund failed',
        _ => 'Refund in progress',
      };
    }
    return switch (status) {
      'PAID' => 'Paid',
      'FAILED' => 'Failed',
      'REFUNDED' => 'Refunded',
      _ => 'Pending',
    };
  }
}

/// Where a profile is edited from: what the form holds.
class ProfileEdit {
  const ProfileEdit({
    required this.fullName,
    required this.email,
    this.dob,
    this.clearDob = false,
    this.gender,
    this.city,
    this.full = false,
    this.bloodGroup = '',
    this.tshirtSize = '',
    this.preferredSports = const [],
    this.playingLevel = '',
    this.about = '',
    this.altPhone = '',
    this.emergencyName = '',
    this.emergencyRelation = '',
    this.emergencyPhone = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.state = '',
    this.pincode = '',
    this.idDocType = '',
  });

  final String fullName;
  final String email;
  final DateTime? dob;
  final bool clearDob;
  final Gender? gender;
  final String? city;

  /// True for the Personal Information page, which sends every field (an empty one clears it); false sends only the basics.
  final bool full;
  final String bloodGroup;
  final String tshirtSize;
  final List<String> preferredSports;
  final String playingLevel;
  final String about;
  final String altPhone;
  final String emergencyName;
  final String emergencyRelation;
  final String emergencyPhone;
  final String addressLine1;
  final String addressLine2;
  final String state;
  final String pincode;
  final String idDocType;
}
