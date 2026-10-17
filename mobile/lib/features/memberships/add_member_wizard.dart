// The Add Member wizard's rules — a port of src/features/memberships/add-member-wizard.ts so the web
// and the app validate, label and save a new member the same way. Pure Dart: the screen only draws
// what this decides.
//
// Four steps: Personal Information → Select Plan → Review & Confirm → Payment. A member's court and
// timings are the plan's own (set when the plan was created), so there is no schedule step.

import '../../data/models/membership.dart';
import 'membership_charges.dart';

/// 0-based step index → title, the one-line hint under it, and the short label under its circle.
const addMemberSteps = <({String title, String hint, String label})>[
  (title: 'Personal Information', hint: 'Basic details', label: 'Personal'),
  (title: 'Select Plan', hint: 'Choose membership plan', label: 'Plan'),
  (title: 'Review & Confirm', hint: 'Verify details', label: 'Review'),
  (title: 'Payment', hint: 'Complete registration', label: 'Payment'),
];

const addMemberLastStep = 3;

const addMemberCountryCodes = ['+91', '+1', '+44', '+971'];

/// Stored value → label, exactly the web's list.
const addMemberGenders = <({String value, String label})>[
  (value: '', label: 'Select'),
  (value: 'male', label: 'Male'),
  (value: 'female', label: 'Female'),
  (value: 'other', label: 'Other'),
];

enum AddMemberPaymentTab {
  link('Generate Payment Link', 'Create a Razorpay payment link'),
  offline('Record Offline Payment', 'Cash, Bank Transfer, etc.'),
  paid('Mark as Paid', 'If already paid');

  const AddMemberPaymentTab(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

const addMemberPaymentMethods = ['Cash', 'Bank Transfer', 'UPI', 'Other'];

/// One court / day / time slot a plan reserves — the member just joins it.
class PlanSlot {
  const PlanSlot({
    required this.batchId,
    required this.courtId,
    required this.courtName,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
  });

  final String batchId;
  final String courtId;
  final String courtName;

  /// 0 = Sunday … 6 = Saturday.
  final List<int> daysOfWeek;

  /// "HH:MM".
  final String startTime;
  final String endTime;
}

/// The plan's slots, ordered by court then start time. Empty when the plan reserves none.
List<PlanSlot> planSlotsFor(List<AssignableBatch> batches, String? planId) {
  if (planId == null || planId.isEmpty) return const [];
  final slots = [
    for (final b in batches)
      if (b.planId == planId)
        PlanSlot(
          batchId: b.batchId,
          courtId: b.courtId,
          courtName: b.courtName.isEmpty ? 'Court' : b.courtName,
          daysOfWeek: ([...b.daysOfWeek]..sort()),
          startTime: b.startTime.length >= 5 ? b.startTime.substring(0, 5) : b.startTime,
          endTime: b.endTime.length >= 5 ? b.endTime.substring(0, 5) : b.endTime,
        ),
  ];
  slots.sort((a, b) {
    final byCourt = a.courtName.compareTo(b.courtName);
    return byCourt != 0 ? byCourt : a.startTime.compareTo(b.startTime);
  });
  return slots;
}

class AddMemberDraft {
  String fullName = '';
  String countryCode = '+91';
  String phone = '';
  String email = '';
  DateTime? dateOfBirth;
  String gender = '';
  String address = '';
  String city = '';
  String pincode = '';
  String emergencyName = '';
  String emergencyCountryCode = '+91';
  String emergencyPhone = '';
  bool sendWelcome = true;

  String planId = '';
  String planName = '';
  DateTime startDate = DateTime.now();
  int durationDays = 0;
  int membershipFeeInr = 0;
  int registrationFeeInr = 0;
  double gstPercent = 0;

  AddMemberPaymentTab paymentTab = AddMemberPaymentTab.link;

  /// 0 until the member reaches Payment — then the plan's total, editable.
  int paymentAmount = 0;
  DateTime paymentDate = DateTime.now();
  String paymentMethod = 'Cash';
  String paymentReference = '';
  String receivedFrom = '';
  String collectedBy = '';
  String paymentNotes = '';
}

MembershipCharges addMemberCharges(AddMemberDraft d) => computeMembershipCharges(
      feeInr: d.membershipFeeInr,
      gstPercent: d.gstPercent,
      registrationInr: d.registrationFeeInr,
    );

final _indianMobile = RegExp(r'^[6-9]\d{9}$');
final _nameRe = RegExp(r"^[A-Za-z][A-Za-z .'-]{1,59}$");
final _cityRe = RegExp(r"^[A-Za-z][A-Za-z .'-]{1,49}$");
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _pincodeRe = RegExp(r'^[1-9]\d{5}$');

String _required(String label) => '$label is required.';
String _invalid(String label) => '$label is invalid.';

/// The number typed into the phone box with the dialling code peeled back off the front if it was
/// pasted in whole.
String addMemberLocalDigits(String countryCode, String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final code = countryCode.replaceAll(RegExp(r'\D'), '');
  return code.isNotEmpty && digits.startsWith(code) && digits.length > code.length ? digits.substring(code.length) : digits;
}

String? _phoneError(String countryCode, String phone, String label) {
  if (phone.trim().isEmpty) return _required(label);
  final digits = addMemberLocalDigits(countryCode, phone);
  if (countryCode == '+91') return _indianMobile.hasMatch(digits) ? null : _invalid(label);
  return digits.length >= 7 && digits.length <= 14 ? null : _invalid(label);
}

String? _nameError(String name, String label) {
  if (name.trim().isEmpty) return _required(label);
  return _nameRe.hasMatch(name.trim()) ? null : _invalid(label);
}

/// What the phone is sent as: a bare 10-digit number for +91, else "+code digits".
String addMemberComposePhone(String countryCode, String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return countryCode == '+91' ? digits : '$countryCode $digits';
}

/// Every field's own error for [step] (0-based), keyed by field name.
Map<String, String> addMemberFieldErrors(int step, AddMemberDraft d, {DateTime? now}) {
  final errors = <String, String>{};
  final today = now ?? DateTime.now();

  if (step == 0) {
    final name = _nameError(d.fullName, 'Full name');
    if (name != null) errors['fullName'] = name;
    final phone = _phoneError(d.countryCode, d.phone, 'Phone number');
    if (phone != null) errors['phone'] = phone;
    if (d.email.trim().isNotEmpty && !_emailRe.hasMatch(d.email.trim())) errors['email'] = _invalid('Email address');
    final dob = d.dateOfBirth;
    if (dob != null) {
      final ageYears = today.difference(dob).inDays / 365.25;
      if (dob.isAfter(today) || ageYears > 120) errors['dateOfBirth'] = _invalid('Date of birth');
    }
    if (d.city.trim().isNotEmpty && !_cityRe.hasMatch(d.city.trim())) errors['city'] = _invalid('City');
    if (d.pincode.trim().isNotEmpty && !_pincodeRe.hasMatch(d.pincode.trim())) errors['pincode'] = _invalid('Pincode');
    if (d.emergencyName.trim().isNotEmpty) {
      final n = _nameError(d.emergencyName, 'Emergency contact name');
      if (n != null) errors['emergencyName'] = n;
    }
    if (d.emergencyPhone.trim().isNotEmpty) {
      final p = _phoneError(d.emergencyCountryCode, d.emergencyPhone, 'Emergency contact number');
      if (p != null) errors['emergencyPhone'] = p;
    }
  }

  if (step == 1) {
    if (d.planId.isEmpty) {
      errors['planId'] = _required('Membership plan');
    } else if (d.durationDays <= 0) {
      errors['planId'] = _invalid('Membership plan');
    }
    if (d.registrationFeeInr < 0) errors['registrationFeeInr'] = _invalid('Registration fee');
    // GST tops out at 28% (the highest standard slab); anything above is a typo.
    if (d.gstPercent < 0 || d.gstPercent > 28) errors['gstPercent'] = _invalid('GST');
  }

  if (step == addMemberLastStep) {
    if (d.paymentAmount <= 0) errors['paymentAmount'] = _required('Payment amount');
    if (d.paymentTab != AddMemberPaymentTab.link) {
      if (d.receivedFrom.trim().isEmpty) errors['receivedFrom'] = _required('Received from');
      if (d.collectedBy.trim().isEmpty) errors['collectedBy'] = _required('Collected by');
      if ((d.paymentMethod == 'UPI' || d.paymentMethod == 'Bank Transfer') && d.paymentReference.trim().isEmpty) {
        errors['paymentReference'] = _required('Reference / Transaction ID');
      }
    }
  }
  return errors;
}

/// The first error on [step], or null when it is complete.
String? addMemberValidateStep(int step, AddMemberDraft d, {DateTime? now}) {
  final errors = addMemberFieldErrors(step, d, now: now);
  return errors.isEmpty ? null : errors.values.first;
}

/// The furthest step reachable — a step only opens once everything before it is valid.
int addMemberFurthestStep(AddMemberDraft d, {DateTime? now}) {
  for (var step = 0; step <= addMemberLastStep; step++) {
    if (addMemberValidateStep(step, d, now: now) != null) return step;
  }
  return addMemberLastStep;
}

/// The member's address as one line: "street, city - pincode".
String? addMemberComposeAddress(AddMemberDraft d) {
  final line = [d.address.trim(), d.city.trim()].where((p) => p.isNotEmpty).join(', ');
  final pin = d.pincode.trim();
  final full = [line, pin].where((p) => p.isNotEmpty).join(' - ');
  return full.isEmpty ? null : full;
}

/// The emergency contact, kept in the member's notes (there is no column of its own for it).
String? addMemberComposeNotes(AddMemberDraft d) {
  final name = d.emergencyName.trim();
  final phone = d.emergencyPhone.trim();
  if (name.isEmpty && phone.isEmpty) return null;
  final number = phone.isEmpty ? '' : '${d.emergencyCountryCode} $phone'.trim();
  return 'Emergency contact: ${[name, number].where((p) => p.isNotEmpty).join(' — ')}';
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _groupedInr(int v) {
  final s = v.abs().toString();
  if (s.length <= 3) return s;
  final head = s.substring(0, s.length - 3);
  final grouped = head.replaceAllMapped(RegExp(r'\B(?=(\d{2})+(?!\d))'), (_) => ',');
  return '$grouped,${s.substring(s.length - 3)}';
}

/// The offline-payment details the payment RPC has no column for, folded into the membership's notes.
String? addMemberComposePaymentNotes(AddMemberDraft d) {
  if (d.paymentTab == AddMemberPaymentTab.link) return null;
  final who = [
    if (d.receivedFrom.trim().isNotEmpty) 'received from ${d.receivedFrom.trim()}',
    if (d.collectedBy.trim().isNotEmpty) 'collected by ${d.collectedBy.trim()}',
  ].join(', ');
  final parts = [
    'Payment: ₹${_groupedInr(d.paymentAmount)} on ${_isoDate(d.paymentDate)} via ${d.paymentMethod}.',
    if (d.paymentReference.trim().isNotEmpty) 'Ref: ${d.paymentReference.trim()}.',
    if (who.isNotEmpty) '${who[0].toUpperCase()}${who.substring(1)}.',
    if (d.paymentNotes.trim().isNotEmpty) d.paymentNotes.trim(),
  ];
  return parts.join(' ');
}

/// Both note sources joined, or null when neither has anything.
String? addMemberNotes(AddMemberDraft d) {
  final all = [addMemberComposeNotes(d), addMemberComposePaymentNotes(d)].whereType<String>().toList();
  return all.isEmpty ? null : all.join('\n');
}

/// Splits a trailing bracketed qualifier off a plan's name: "Batch 1(5 A.M to 6 A.M)" →
/// ("Batch 1", "(5 A.M to 6 A.M)"). Mirrors the web's `splitPlanName`.
({String main, String? detail}) splitPlanName(String name) {
  final match = RegExp(r'^(.*\S)\s*(\([^()]*\))$').firstMatch(name.trim());
  if (match == null) return (main: name.trim(), detail: null);
  return (main: match.group(1)!.trim(), detail: match.group(2));
}

/// The checklist shown on a plan card: the plan's own features, else the usual terms for its type.
List<String> addMemberPlanFeatures(MembershipPlan plan, String billingInterval) {
  if (plan.features.isNotEmpty) return plan.features;
  if (plan.planType == 'RECURRING') {
    return ['Auto-renews $billingInterval', 'Recurring payment', 'Continuous membership', 'Cancel anytime'];
  }
  return ['Fixed membership period', 'One-time payment', 'Valid until expiry', 'Manual renewal required'];
}

/// The stored phone is bare digits for +91 and "+code digits" otherwise — the reverse of
/// [addMemberComposePhone], for pre-filling the edit form.
({String code, String number}) addMemberSplitPhone(String stored) {
  final m = RegExp(r'^(\+\d{1,3})\s+(.*)$').firstMatch(stored.trim());
  if (m != null) return (code: m.group(1)!, number: m.group(2)!.replaceAll(RegExp(r'\D'), ''));
  return (code: '+91', number: stored.replaceAll(RegExp(r'\D'), ''));
}

// ── Billing periods ──────────────────────────────────────────────────────

/// Whole months in a billing period: 30 → 1, 90 → 3, 180 → 6, 365 → 12. Null for a custom length under
/// four weeks, which stays a plain number of days.
int? billingPeriodMonths(int durationDays) => durationDays >= 28 ? ((durationDays / 30).round()).clamp(1, 1 << 30) : null;

/// A period starting on [from], ending where the next one begins: the same day next month (14 Oct → 14 Nov).
/// Month ends clamp the way Razorpay and Postgres do (31 Jan + 1 month = 28 Feb).
DateTime addBillingPeriod(DateTime from, int durationDays) {
  final months = billingPeriodMonths(durationDays);
  if (months == null) return DateTime(from.year, from.month, from.day + durationDays);
  final total = from.month - 1 + months;
  final year = from.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, from.day > lastDay ? lastDay : from.day);
}

/// The last day of the first period — the "Plan End Date" shown while a membership is being set up.
DateTime periodEndDate(DateTime start, int durationDays) {
  final next = addBillingPeriod(start, durationDays);
  return DateTime(next.year, next.month, next.day - 1);
}

/// What is saved as the membership fee, registration fee: the fee is ALWAYS the plan's price (it is what
/// AutoPay charges every cycle); anything on top — the registration / joining fee, or a higher amount typed
/// under "Edit Amount" — is a one-time extra in the registration fee, so it is never repeated.
({int feeInr, int registrationInr}) membershipFeeSplit({
  required int planPriceInr,
  required int gstAmountInr,
  required int registrationInr,
  required int paymentAmountInr,
}) =>
    (
      feeInr: planPriceInr,
      registrationInr: paymentAmountInr > 0 ? (paymentAmountInr - planPriceInr - gstAmountInr).clamp(0, 1 << 30) : registrationInr,
    );

/// How the member's AutoPay is doing, in words an owner can act on.
({String label, String detail}) autoPayStatusLabel(String status) => switch (status) {
      'created' => (label: 'Awaiting Authorisation', detail: "The member hasn't approved the payment link yet. Charging starts once they do."),
      'authenticated' => (label: 'Authorised', detail: 'The member approved AutoPay; the first charge is being processed.'),
      'active' => (label: 'Active', detail: 'Charged automatically each cycle on the same day of the month.'),
      'pending' => (label: 'Payment failed — retrying', detail: 'The last charge failed. Razorpay is retrying; the member may need to check their account.'),
      'halted' => (label: 'Stopped — payment failed', detail: 'Retries ran out. The member must authorise again or pay another way.'),
      'cancelled' => (label: 'Cancelled', detail: 'AutoPay was stopped. The membership runs to its paid-until date.'),
      'completed' => (label: 'Completed', detail: 'AutoPay ran its full course.'),
      _ => (label: status, detail: ''),
    };

/// "every month", "every 3 months", "every year".
String autoPayCadence(int? intervalMonths) {
  if (intervalMonths == null || intervalMonths <= 1) return 'every month';
  if (intervalMonths == 12) return 'every year';
  if (intervalMonths % 12 == 0) return 'every ${intervalMonths ~/ 12} years';
  return 'every $intervalMonths months';
}

/// A subscription that has already collected a charge is active, whatever the last event said — Razorpay can
/// deliver "authenticated" after "charged", and older rows were left on the earlier status.
String effectiveAutoPayStatus(String status, int chargeCount) =>
    (status == 'authenticated' || status == 'created') && chargeCount > 0 ? 'active' : status;

/// The date the next AutoPay charge is due: shown whenever AutoPay is running — charging, retrying, or
/// authorised with the first charge already collected. Razorpay's own date when we have it, else the
/// membership's next payment date. Null before the first charge and once AutoPay has stopped.
DateTime? autoPayNextCharge({required String status, required int chargeCount, required DateTime? nextChargeDate, required DateTime membershipEndDate}) {
  final s = effectiveAutoPayStatus(status, chargeCount);
  if (s != 'active' && s != 'pending') return null;
  return nextChargeDate ?? membershipEndDate;
}

/// AutoPay that can still charge the member (set up, authorised, charging, retrying) — the kind that must be
/// cancelled before a member can be deleted. A cancelled / completed one cannot.
bool isAutoPayLive(String status, int chargeCount) {
  const live = {'created', 'authenticated', 'active', 'pending', 'halted'};
  return live.contains(effectiveAutoPayStatus(status, chargeCount));
}
