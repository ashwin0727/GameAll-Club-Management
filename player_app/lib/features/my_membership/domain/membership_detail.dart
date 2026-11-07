/// One of the player's active memberships with everything the Membership Details page shows. Read from the database function
/// `get_my_membership_details` (migration 0180), which joins memberships, plans, the allocated batch (court, sport, days, time), the venue,
/// payments, AutoPay and the member's bookings.
class MembershipDetail {
  const MembershipDetail({
    required this.id,
    required this.ref,
    required this.planName,
    required this.venue,
    this.description,
    this.badge,
    this.durationDays,
    this.priceInr,
    this.registrationFeeInr = 0,
    this.totalInr,
    this.paidInr = 0,
    this.features = const [],
    this.startDate,
    this.endDate,
    this.memberSince,
    this.autoRenew = false,
    this.autopayStatus,
    this.paymentMethod,
    this.payState = 'PAID',
    this.slot,
    this.usage = const MembershipUsage(),
    this.payments = const [],
    this.bookings = const [],
    this.limited = false,
  });

  factory MembershipDetail.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? map(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : null;
    List<Map<String, dynamic>> list(Object? v) => [
      for (final e in (v as List<dynamic>? ?? const []))
        if (e is Map) e.cast<String, dynamic>(),
    ];
    return MembershipDetail(
      id: j['id'] as String,
      ref: (j['membershipRef'] as String?) ?? '',
      planName: (j['planName'] as String?) ?? 'Membership',
      description: _clean(j['description'] as String?),
      badge: _clean(j['badge'] as String?),
      durationDays: (j['durationDays'] as num?)?.toInt(),
      priceInr: (j['priceInr'] as num?)?.toInt(),
      registrationFeeInr: (j['registrationFeeInr'] as num?)?.toInt() ?? 0,
      totalInr: (j['totalInr'] as num?)?.toInt(),
      paidInr: (j['paidInr'] as num?)?.toInt() ?? 0,
      features: [
        for (final f in (j['features'] as List<dynamic>? ?? const []))
          if (f != null && f.toString().trim().isNotEmpty) f.toString().trim(),
      ],
      startDate: _date(j['startDate']),
      endDate: _date(j['endDate']),
      memberSince: _date(j['memberSince']),
      autoRenew: j['autoRenew'] == true,
      autopayStatus: j['autopayStatus'] as String?,
      paymentMethod: _clean(j['paymentMethod'] as String?),
      payState: (j['payState'] as String?) ?? 'PAID',
      venue: MembershipVenue.fromJson(map(j['venue']) ?? const {}),
      slot: map(j['slot']) == null
          ? null
          : MembershipSlot.fromJson(map(j['slot'])!),
      usage: map(j['usage']) == null
          ? const MembershipUsage()
          : MembershipUsage.fromJson(map(j['usage'])!),
      payments: [
        for (final p in list(j['payments'])) MembershipPayment.fromJson(p),
      ],
      bookings: [
        for (final b in list(j['bookings'])) MembershipBooking.fromJson(b),
      ],
    );
  }

  final String id;

  /// "MBR-CHZ-000458"
  final String ref;
  final String planName;
  final String? description;
  final String? badge;
  final int? durationDays;
  final int? priceInr;
  final int registrationFeeInr;
  final int? totalInr;
  final int paidInr;
  final List<String> features;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? memberSince;
  final bool autoRenew;

  /// created | authenticated | active | halted | pending | completed | cancelled… (null: not an AutoPay membership)
  final String? autopayStatus;
  final String? paymentMethod;

  /// PAID | PENDING | FAILED
  final String payState;
  final MembershipVenue venue;
  final MembershipSlot? slot;
  final MembershipUsage usage;
  final List<MembershipPayment> payments;
  final List<MembershipBooking> bookings;

  /// True when only the short Home summary was available (the database function is not installed yet).
  final bool limited;

  bool get isPaid => payState == 'PAID';
  bool get hasAutopay => autopayStatus != null;

  /// "Monthly", "Quarterly", "Half-yearly", "Yearly" or "45 days".
  String get periodLabel => switch (durationDays) {
    null => 'Membership',
    >= 25 && <= 45 => 'Monthly',
    >= 80 && <= 100 => 'Quarterly',
    >= 170 && <= 200 => 'Half-yearly',
    >= 350 && <= 380 => 'Yearly',
    final d => '$d days',
  };

  /// "month", "3 months", "6 months", "year" — for "₹3,000 / month".
  String get pricePeriod => switch (durationDays) {
    null => 'plan',
    >= 25 && <= 45 => 'month',
    >= 80 && <= 100 => '3 months',
    >= 170 && <= 200 => '6 months',
    >= 350 && <= 380 => 'year',
    final d => '$d days',
  };

  /// "Active Membership" — or what is wrong with it.
  String get statusPill => switch (payState) {
    'PAID' => 'Active Membership',
    'FAILED' => 'Payment Failed',
    _ => 'Payment Incomplete',
  };

  /// "Active", or "Payment Incomplete" / "Payment Failed" until it is paid.
  String get statusShort => switch (payState) {
    'PAID' => 'Active',
    'FAILED' => 'Payment Failed',
    _ => 'Payment Incomplete',
  };

  /// "Online (UPI)", "UPI AutoPay", "Cash at the club" … or "Not paid yet".
  String get paymentMode {
    if (hasAutopay) return 'UPI AutoPay';
    final m = (paymentMethod ?? '').trim().toLowerCase();
    if (m.isEmpty) return isPaid ? 'Paid at the club' : 'Not paid yet';
    if (m == 'upi') return 'Online (UPI)';
    if (m == 'online' || m == 'razorpay') return 'Online';
    if (m == 'card') return 'Online (Card)';
    if (m == 'cash') return 'Cash at the club';
    return paymentMethod!;
  }

  /// "20 Sessions / Month", or null when there is no allocated slot to count.
  String? get sessionLimitLabel {
    final t = usage.total;
    return t == null ? null : '$t ${t == 1 ? 'Session' : 'Sessions'} / Month';
  }

  /// What is still to pay (never below 0).
  int get balanceInr {
    final total = totalInr ?? 0;
    return total > paidInr ? total - paidInr : 0;
  }
}

class MembershipVenue {
  const MembershipVenue({
    required this.id,
    required this.name,
    this.area,
    this.city,
    this.phone,
    this.imageUrl,
  });

  factory MembershipVenue.fromJson(Map<String, dynamic> j) => MembershipVenue(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? 'Venue',
    area: _clean(j['area'] as String?),
    city: _clean(j['city'] as String?),
    phone: _clean(j['phone'] as String?),
    imageUrl: _clean(j['imageUrl'] as String?),
  );

  final String id;
  final String name;
  final String? area;
  final String? city;
  final String? phone;
  final String? imageUrl;

  /// "Iyyapanthangal, Chennai"
  String get place {
    final a = (area ?? '').trim();
    final c = (city ?? '').trim();
    final showArea = a.isNotEmpty && a.toLowerCase() != c.toLowerCase();
    return [if (showArea) a, c].where((p) => p.isNotEmpty).join(', ');
  }
}

/// The court, sport, weekdays and time the member was allocated.
class MembershipSlot {
  const MembershipSlot({
    this.batchName,
    this.sport,
    this.court,
    this.days = const [],
    this.start,
    this.end,
  });

  factory MembershipSlot.fromJson(Map<String, dynamic> j) => MembershipSlot(
    batchName: _clean(j['batchName'] as String?),
    sport: _clean(j['sport'] as String?),
    court: _clean(j['court'] as String?),
    days: [
      for (final d in (j['daysOfWeek'] as List<dynamic>? ?? const []))
        (d as num).toInt(),
    ],
    start: _clean(j['startTime'] as String?),
    end: _clean(j['endTime'] as String?),
  );

  final String? batchName;
  final String? sport;
  final String? court;

  /// 0 = Sunday … 6 = Saturday
  final List<int> days;
  final String? start;
  final String? end;

  /// "Mon – Fri, 6:00 PM – 7:00 PM"
  String? get label {
    final d = daysLabel(days);
    final t = timeLabel;
    if (d.isEmpty && t == null) return null;
    return [if (d.isNotEmpty) d, ?t].join(', ');
  }

  /// "6:00 PM – 7:00 PM"
  String? get timeLabel => (start == null || end == null)
      ? null
      : '${clock12(start!)} – ${clock12(end!)}';
}

/// "This Month's Usage": how many of the month's sessions have been used.
class MembershipUsage {
  const MembershipUsage({this.total, this.used = 0});

  factory MembershipUsage.fromJson(Map<String, dynamic> j) => MembershipUsage(
    total: (j['sessionsTotal'] as num?)?.toInt(),
    used: (j['sessionsUsed'] as num?)?.toInt() ?? 0,
  );

  /// Sessions this month (null when the member has no allocated slot to count).
  final int? total;
  final int used;

  int get remaining => total == null ? 0 : (total! - used).clamp(0, total!);

  /// 0..1 for the progress bar.
  double get fraction =>
      (total == null || total == 0) ? 0 : (used / total!).clamp(0.0, 1.0);
}

class MembershipPayment {
  const MembershipPayment({
    required this.id,
    required this.amountInr,
    required this.status,
    this.method,
    this.when,
    this.reference,
  });

  factory MembershipPayment.fromJson(Map<String, dynamic> j) =>
      MembershipPayment(
        id: (j['id'] as String?) ?? '',
        amountInr: (j['amountInr'] as num?)?.toInt() ?? 0,
        status: (j['status'] as String?) ?? 'created',
        method: _clean(j['method'] as String?),
        when: _date(j['paidAt']) ?? _date(j['createdAt']),
        reference: _clean(j['reference'] as String?),
      );

  final String id;
  final int amountInr;

  /// paid | created | failed | refunded
  final String status;
  final String? method;
  final DateTime? when;
  final String? reference;

  String get statusLabel => switch (status) {
    'paid' => 'Paid',
    'failed' => 'Failed',
    'refunded' => 'Refunded',
    _ => 'Pending',
  };
}

class MembershipBooking {
  const MembershipBooking({
    required this.id,
    required this.status,
    this.start,
    this.end,
    this.court,
    this.sport,
  });

  factory MembershipBooking.fromJson(Map<String, dynamic> j) =>
      MembershipBooking(
        id: (j['id'] as String?) ?? '',
        status: ((j['status'] as String?) ?? '').toLowerCase(),
        start: _date(j['startTime']),
        end: _date(j['endTime']),
        court: _clean(j['court'] as String?),
        sport: _clean(j['sport'] as String?),
      );

  final String id;

  /// confirmed | completed | cancelled | pending
  final String status;
  final DateTime? start;
  final DateTime? end;
  final String? court;
  final String? sport;

  bool get upcoming =>
      start != null && start!.isAfter(DateTime.now()) && status != 'cancelled';

  String get statusLabel => switch (status) {
    'confirmed' => 'Confirmed',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    _ => 'Pending',
  };
}

// ── labels ──────────────────────────────────────────────────────────────────

/// "6:00 PM" from "18:00" (or "18:00:00").
String clock12(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
  final hour = h % 12 == 0 ? 12 : h % 12;
  return '$hour:$m ${h % 24 < 12 ? 'AM' : 'PM'}';
}

/// "Mon – Fri", "Mon – Sat", "Every day", "Mon, Wed, Fri", "Sat – Sun" — from weekday numbers (0 = Sunday).
String daysLabel(List<int> days) {
  const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final set = {for (final d in days) d % 7};
  if (set.isEmpty) return '';
  if (set.length == 7) return 'Every day';
  // Monday first, so Mon – Sat reads as one run and Sunday comes last
  final order = [1, 2, 3, 4, 5, 6, 0].where(set.contains).toList();
  final runs = <List<int>>[];
  for (final d in order) {
    final pos = d == 0 ? 7 : d;
    if (runs.isNotEmpty &&
        (runs.last.last == 0 ? 7 : runs.last.last) + 1 == pos) {
      runs.last.add(d);
    } else {
      runs.add([d]);
    }
  }
  return runs
      .map(
        (r) => r.length >= 3 || (r.length == 2 && runs.length == 1)
            ? '${names[r.first]} – ${names[r.last]}'
            : r.map((d) => names[d]).join(', '),
      )
      .join(', ');
}

/// "01 Sep 2026"
String fmtDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
