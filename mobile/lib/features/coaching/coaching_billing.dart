// How a monthly coaching program is charged and shown — the same rules as the web's billing-schedule.ts,
// kept pure so they are tested: calendar-month dates, the program's length, the fee per session, and the
// next payment.

import '../../data/models/coaching.dart';

/// The dates a monthly program charges the student: the start date, then the same day of each following
/// month (14 Oct → 14 Nov → 14 Dec …). Month ends clamp the way Razorpay does (31 Jan → 28 Feb → 31 Mar).
///
/// The real schedule follows the day the student approves the mandate; this is what it is expected to be
/// if they approve on the start date.
List<DateTime> chargeDates(DateTime start, int cycles) {
  final count = cycles < 1 ? 1 : cycles;
  return [
    for (var i = 0; i < count; i++)
      () {
        final total = start.month - 1 + i;
        final year = start.year + total ~/ 12;
        final month = total % 12 + 1;
        final lastDay = DateTime(year, month + 1, 0).day;
        return DateTime(year, month, start.day > lastDay ? lastDay : start.day);
      }(),
  ];
}

/// How long the program runs, from its own start and end dates: "24 weeks · 6 months". Null without both.
String? programLengthLabel(DateTime? start, DateTime? end) {
  if (start == null || end == null) return null;
  final days = DateTime(end.year, end.month, end.day).difference(DateTime(start.year, start.month, start.day)).inDays + 1;
  if (days <= 0) return null;
  final weeks = (days / 7).round().clamp(1, 100000);
  final months = (days / 30.4).round().clamp(1, 100000);
  return '$weeks ${weeks == 1 ? 'week' : 'weeks'} · $months ${months == 1 ? 'month' : 'months'}';
}

/// What one session works out to: the total fee spread over the program's sessions. Null when unknown.
int? perSessionMinor(int totalMinor, int? sessionCount) {
  if (sessionCount == null || sessionCount <= 0 || totalMinor <= 0) return null;
  return (totalMinor / sessionCount).round();
}

/// The date the next AutoPay charge is due — only while the subscription is actually charging.
String? nextPaymentDate(EnrollmentBilling? billing) {
  if (billing == null || !billing.isSubscription) return null;
  if (billing.status != 'ACTIVE' && billing.status != 'PENDING') return null;
  return billing.currentEnd;
}

/// Charges still to come: the total minus those already collected (never below zero).
int chargesLeft(EnrollmentBilling billing) {
  final left = billing.totalCycles - billing.chargeCount;
  return left < 0 ? 0 : left;
}

/// The charges still to come, each "not paid yet": the next payment date then the same day of each
/// following month, capped at what is left on the plan. Collected charges are rows of the payments list,
/// so a student's paid and upcoming charges never overwrite each other.
List<DateTime> upcomingCharges(EnrollmentBilling? billing, {int limit = 3}) {
  final next = DateTime.tryParse(nextPaymentDate(billing) ?? '');
  if (billing == null || next == null) return const [];
  final count = chargesLeft(billing) < limit ? chargesLeft(billing) : limit;
  return count > 0 ? chargeDates(next, count) : const [];
}
