// The parts of the signed-in player's Home page that come from the clubs' own records, found by the player's phone number
// (database function `get_player_dashboard`, migration 0169). Every list can hold several entries: a player may have more than one
// membership, more than one coaching enrolment and several guest bookings, at several clubs.

import '../../venues/domain/venue.dart' show rupees;

const _weekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// "Mon - Fri", "Sat & Sun", "Mon, Wed, Fri": the days a batch runs, from the database's 0 = Sunday ... 6 = Saturday.
String describeDays(List<int> days) {
  final d = ({...days}.where((x) => x >= 0 && x <= 6).toList())..sort();
  if (d.isEmpty) return '';
  if (d.length == 7) return 'Every day';
  // Monday to Friday and the like read as a range: a run of three or more consecutive days, Monday first.
  final monFirst = d.map((x) => (x + 6) % 7).toList()..sort();
  var consecutive = monFirst.length >= 3;
  for (var i = 1; i < monFirst.length; i++) {
    if (monFirst[i] != monFirst[i - 1] + 1) consecutive = false;
  }
  String name(int monFirstIndex) => _weekdayShort[(monFirstIndex + 1) % 7];
  if (consecutive) return '${name(monFirst.first)} - ${name(monFirst.last)}';
  if (monFirst.length == 2) {
    return '${name(monFirst[0])} & ${name(monFirst[1])}';
  }
  return monFirst.map(name).join(', ');
}

/// "18:00" -> "6:00 PM"
String clock12(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts[1].padLeft(2, '0');
  final hour = h % 12 == 0 ? 12 : h % 12;
  return '$hour:$m ${h < 12 ? 'AM' : 'PM'}';
}

class ActiveMembership {
  const ActiveMembership({
    required this.id,
    required this.planName,
    required this.venueName,
    this.batchName,
    this.days = const [],
    this.startTime,
    this.endTime,
    this.courtName,
    this.endDate,
    this.paymentIncomplete = false,
  });

  factory ActiveMembership.fromJson(Map<String, dynamic> json) =>
      ActiveMembership(
        id: json['id'] as String,
        planName: (json['planName'] as String?) ?? 'Membership',
        venueName: (json['venueName'] as String?) ?? '',
        batchName: json['batchName'] as String?,
        days: [
          for (final d in (json['daysOfWeek'] as List<dynamic>? ?? const []))
            (d as num).toInt(),
        ],
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
        courtName: json['courtName'] as String?,
        endDate: json['endDate'] == null
            ? null
            : DateTime.tryParse(json['endDate'] as String),
        paymentIncomplete: json['paymentIncomplete'] == true,
      );

  final String id;
  final String planName;
  final String venueName;
  final String? batchName;
  final List<int> days;
  final String? startTime;
  final String? endTime;
  final String? courtName;
  final DateTime? endDate;

  /// Not paid in full yet (or AutoPay is failing): shown with a "Payment Incomplete" tag instead of "Active".
  final bool paymentIncomplete;

  /// "Mon - Fri · 6:00 PM - 7:00 PM", or just the club when the membership has no fixed batch.
  String get when {
    final dayText = describeDays(days);
    final timeText = (startTime != null && endTime != null)
        ? '${clock12(startTime!)} - ${clock12(endTime!)}'
        : '';
    final parts = [dayText, timeText].where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? venueName : parts.join('  ·  ');
  }

  /// The second line of a card: the batch (e.g. "Evening Play"), or the club.
  String get subtitle => (batchName != null && batchName!.trim().isNotEmpty)
      ? batchName!
      : planName;
}

class ActiveCoaching {
  const ActiveCoaching({
    required this.id,
    required this.programName,
    required this.venueName,
    this.coachName,
    this.nextSession,
    this.nextSessionEnd,
    this.paymentIncomplete = false,
  });

  factory ActiveCoaching.fromJson(Map<String, dynamic> json) => ActiveCoaching(
    id: json['id'] as String,
    programName: (json['programName'] as String?) ?? 'Coaching',
    venueName: (json['venueName'] as String?) ?? '',
    coachName: json['coachName'] as String?,
    nextSession: json['nextSession'] == null
        ? null
        : DateTime.parse(json['nextSession'] as String).toLocal(),
    nextSessionEnd: json['nextSessionEnd'] == null
        ? null
        : DateTime.parse(json['nextSessionEnd'] as String).toLocal(),
    paymentIncomplete: json['paymentIncomplete'] == true,
  );

  final String id;
  final String programName;
  final String venueName;
  final String? coachName;
  final DateTime? nextSession;
  final DateTime? nextSessionEnd;

  /// Not paid in full yet (or AutoPay is failing): shown with a "Payment Incomplete" tag instead of "Enrolled".
  final bool paymentIncomplete;
}

class GuestBookingSummary {
  const GuestBookingSummary({
    this.count = 0,
    this.nextStart,
    this.nextEnd,
    this.nextVenue,
    this.nextCourt,
  });

  factory GuestBookingSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GuestBookingSummary();
    final next = json['next'] is Map
        ? (json['next'] as Map).cast<String, dynamic>()
        : null;
    return GuestBookingSummary(
      count: (json['count'] as num?)?.toInt() ?? 0,
      nextStart: next == null
          ? null
          : DateTime.parse(next['startTime'] as String).toLocal(),
      nextEnd: next == null
          ? null
          : DateTime.parse(next['endTime'] as String).toLocal(),
      nextVenue: next?['venueName'] as String?,
      nextCourt: next?['courtName'] as String?,
    );
  }

  final int count;
  final DateTime? nextStart;
  final DateTime? nextEnd;
  final String? nextVenue;
  final String? nextCourt;
}

enum ScheduleKind { membership, coaching, guest }

class ScheduleItem {
  const ScheduleItem({
    required this.kind,
    required this.title,
    required this.venueName,
    required this.startTime,
    required this.endTime,
    this.courtName,
    this.status = 'confirmed',
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
    kind: switch (json['kind']) {
      'membership' => ScheduleKind.membership,
      'coaching' => ScheduleKind.coaching,
      _ => ScheduleKind.guest,
    },
    title: (json['title'] as String?) ?? '',
    venueName: (json['venueName'] as String?) ?? '',
    courtName: json['courtName'] as String?,
    startTime: DateTime.parse(json['startTime'] as String).toLocal(),
    endTime: DateTime.parse(json['endTime'] as String).toLocal(),
    status: ((json['status'] as String?) ?? 'confirmed').toLowerCase(),
  );

  final ScheduleKind kind;
  final String title;
  final String venueName;
  final String? courtName;
  final DateTime startTime;
  final DateTime endTime;
  final String status;

  /// "Upcoming" while it is later than now, otherwise "Confirmed" (the design's two states).
  String get statusLabel => status == 'in_progress' ? 'Now' : 'Confirmed';
}

enum PendingPaymentKind { membership, coaching, booking }

/// Something the player signed up for or booked but has not finished paying for (`pendingPayments` of `get_player_dashboard`, migration
/// 0177). It is not "Active" / "Enrolled" until it is paid; until then Home shows a prompt with a way to pay.
class PendingPayment {
  const PendingPayment({
    required this.kind,
    required this.id,
    required this.title,
    required this.venueName,
    this.failed = false,
    this.overdue = false,
    this.autopay = false,
    this.startTime,
    this.balanceInr,
  });

  factory PendingPayment.fromJson(Map<String, dynamic> json) => PendingPayment(
    kind: switch (json['kind']) {
      'membership' => PendingPaymentKind.membership,
      'coaching' => PendingPaymentKind.coaching,
      _ => PendingPaymentKind.booking,
    },
    id: (json['id'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    venueName: (json['venueName'] as String?) ?? '',
    failed: json['state'] == 'FAILED',
    overdue: json['overdue'] == true,
    autopay: json['mode'] == 'AUTOPAY',
    balanceInr: json['balance'] == true ? (json['balanceInr'] as num?)?.toInt() : null,
    startTime: json['startTime'] == null
        ? null
        : DateTime.tryParse(json['startTime'] as String)?.toLocal(),
  );

  final PendingPaymentKind kind;

  /// The membership / coaching enrolment / booking id.
  final String id;

  /// The plan name, the programme name, or "Guest Booking" / "Court Booking".
  final String title;
  final String venueName;

  /// A payment failed, AutoPay is halted or retrying, or the payment link ran out.
  final bool failed;

  /// Its start date has passed and it is still unpaid.
  final bool overdue;

  /// Paid by UPI AutoPay (memberships, monthly coaching) rather than a one-time payment link.
  final bool autopay;

  /// A booking's start.
  final DateTime? startTime;

  /// A booking whose advance is paid: what is still owed (null for everything else). Its prompt asks for the balance as the booking ends.
  final int? balanceInr;

  bool get isBalance => balanceInr != null;

  /// A payment that went wrong or ran late is spoken about more firmly than one that has only just been started.
  bool get urgent => failed || overdue;
}

/// The words of one payment prompt.
class PaymentPromptCopy {
  const PaymentPromptCopy({
    required this.title,
    required this.message,
    required this.button,
  });
  final String title;
  final String message;
  final String button;
}

/// What a payment prompt says. Kept here, away from the widget, so the wording is in one place.
PaymentPromptCopy paymentPromptCopy(PendingPayment p) {
  final retry = p.failed ? 'Retry payment' : 'Complete payment';
  switch (p.kind) {
    case PendingPaymentKind.membership:
      return p.urgent
          ? PaymentPromptCopy(
              title: 'Membership AutoPay not completed',
              message:
                  'Your ${p.title} membership at ${p.venueName} is waiting on its AutoPay. Please complete the payment now to keep it. If it stays unpaid, your membership may be cancelled.',
              button: retry,
            )
          : PaymentPromptCopy(
              title: 'Complete your membership payment',
              message:
                  'Your ${p.title} membership at ${p.venueName} starts once the payment is done. Set up AutoPay to confirm it.',
              button: retry,
            );
    case PendingPaymentKind.coaching:
      final what = p.autopay ? 'AutoPay' : 'payment';
      return p.urgent
          ? PaymentPromptCopy(
              title: p.autopay
                  ? 'Coaching AutoPay not completed'
                  : 'Coaching payment not completed',
              message:
                  'Your ${p.title} coaching at ${p.venueName} is waiting on its $what. Please complete the payment now to keep your place. If it stays unpaid, your coaching may be cancelled.',
              button: retry,
            )
          : PaymentPromptCopy(
              title: 'Complete your coaching payment',
              message:
                  'Your place in ${p.title} at ${p.venueName} is confirmed once the $what is done.',
              button: retry,
            );
    case PendingPaymentKind.booking:
      final when = p.startTime == null
          ? ''
          : ' for ${_weekdayShort[p.startTime!.weekday % 7]}, ${p.startTime!.day} ${_monthShort[p.startTime!.month - 1]} · ${clock12('${p.startTime!.hour}:${p.startTime!.minute}')}';
      if (p.isBalance) {
        final left = rupees(p.balanceInr!);
        return PaymentPromptCopy(
          title: 'Balance payment pending for ${p.title} at ${p.venueName}',
          message: p.overdue
              ? 'Your booking has ended. Please pay the remaining $left$when to complete it.'
              : 'Your booking is about to end. Pay the remaining $left$when now, online.',
          button: 'Pay balance',
        );
      }
      return PaymentPromptCopy(
        title: 'Payment pending for ${p.title} at ${p.venueName}',
        message: p.failed
            ? "Your last payment didn't go through. Please try again to keep your court$when."
            : 'Complete the payment to confirm your court$when.',
        button: retry,
      );
  }
}

const _monthShort = [
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
