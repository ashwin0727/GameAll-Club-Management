// Models for the Profile hub (plan, headline numbers, support, preferences) —
// the Dart side of src/features/profile/types.ts.

/// The signed-in person's own `profiles` row.
class HubProfile {
  const HubProfile({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.avatarUrl,
    required this.role,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String role;
  final DateTime? createdAt;

  factory HubProfile.fromJson(Map<String, dynamic> json) => HubProfile(
        id: json['id'] as String,
        fullName: (json['full_name'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        phone: json['phone'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        role: (json['role'] as String?) ?? 'member',
        createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal(),
      );

  String get roleTitle => switch (role) {
        'admin' => 'Facility Owner',
        'staff' => 'Facility Staff',
        _ => 'Member',
      };
}

/// GameAll's own plan for a facility — a membership fee, not a commission.
class FacilityPlan {
  const FacilityPlan({
    required this.planName,
    required this.priceMinor,
    required this.currency,
    required this.interval,
    required this.status,
    required this.validTill,
    this.features = const [],
    this.isSample = false,
  });

  final String planName;
  final int priceMinor;
  final String currency;

  /// month | quarter | year
  final String interval;

  /// active | cancelled
  final String status;

  /// yyyy-MM-dd — the last day the plan covers.
  final String validTill;
  final List<String> features;

  /// True for the placeholder shown until a real plan is synced in.
  final bool isSample;

  factory FacilityPlan.fromJson(Map<String, dynamic> json) => FacilityPlan(
        planName: json['plan_name'] as String,
        priceMinor: (json['price_minor'] as num).toInt(),
        currency: (json['currency'] as String?) ?? 'INR',
        interval: (json['billing_interval'] as String?) ?? 'month',
        status: (json['status'] as String?) ?? 'active',
        validTill: json['valid_till'] as String,
        features: ((json['features'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(),
      );

  /// Plans and pricing are still being finalised; until a row exists the owner sees this.
  factory FacilityPlan.sample([DateTime? now]) {
    final n = now ?? DateTime.now();
    return FacilityPlan(
      planName: 'Pro Plan',
      priceMinor: 299900,
      currency: 'INR',
      interval: 'month',
      status: 'active',
      validTill: '${n.year}-12-31',
      isSample: true,
      features: const [
        'Unlimited bookings and guest bookings',
        'Memberships, sessions and coaching management',
        'Finance, expenses and Reports & Analytics',
        'Staff roles and permissions',
        'Priority support',
      ],
    );
  }

  /// Active only while not cancelled and the last covered day has not passed.
  bool isActive([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    return status == 'active' && validTill.compareTo(today) >= 0;
  }

  int daysLeft([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return DateTime.parse(validTill).difference(today).inDays;
  }
}

/// This month's headline numbers, plus what the facility has right now.
class HubStats {
  const HubStats({
    required this.bookingsThisMonth,
    required this.activeMembers,
    required this.courts,
    required this.revenueThisMonthMinor,
  });

  final int bookingsThisMonth;
  final int activeMembers;
  final int courts;
  final int revenueThisMonthMinor;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.category,
    required this.subject,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String category;
  final String subject;
  final String status;
  final DateTime? createdAt;

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        id: json['id'] as String,
        category: (json['category'] as String?) ?? 'GENERAL',
        subject: (json['subject'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'OPEN',
        createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal(),
      );
}

const supportCategories = <String, String>{
  'GENERAL': 'General question',
  'BILLING': 'My GameAll plan & billing',
  'BOOKINGS': 'Bookings',
  'PAYMENTS': 'Payments & payouts',
  'TECHNICAL': "Something isn't working",
  'OTHER': 'Other',
};

class NotificationPrefs {
  const NotificationPrefs({
    this.bookings = true,
    this.payments = true,
    this.memberships = true,
    this.reports = false,
  });

  final bool bookings;
  final bool payments;
  final bool memberships;
  final bool reports;

  factory NotificationPrefs.fromJson(Map<String, dynamic>? json) => NotificationPrefs(
        bookings: json?['bookings'] as bool? ?? true,
        payments: json?['payments'] as bool? ?? true,
        memberships: json?['memberships'] as bool? ?? true,
        reports: json?['reports'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'bookings': bookings,
        'payments': payments,
        'memberships': memberships,
        'reports': reports,
      };

  NotificationPrefs copyWith({bool? bookings, bool? payments, bool? memberships, bool? reports}) => NotificationPrefs(
        bookings: bookings ?? this.bookings,
        payments: payments ?? this.payments,
        memberships: memberships ?? this.memberships,
        reports: reports ?? this.reports,
      );
}
