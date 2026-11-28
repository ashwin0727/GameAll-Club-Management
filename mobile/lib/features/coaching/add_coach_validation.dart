// Validation for the Add Coach form's "+ New person" fields — the same rules as the web's add-coach-validation.ts,
// pure so they are tested rather than eyeballed.

import '../../data/models/coaching.dart' show AvailabilityWindow;

final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String email) => _emailRegex.hasMatch(email.trim());

/// Strips everything but digits and caps at 10 — a pasted "+91 98765-43210" never lands in the field.
String sanitizePhoneDigits(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

/// Phone is optional overall, but an entered value must be exactly 10 digits.
bool isValidPhoneDigits(String digits) => digits.isEmpty || digits.length == 10;

const _maxAgeYears = 100;
const _minAgeYears = 18;

DateTime _yearsAgo(DateTime today, int years) => DateTime(today.year - years, today.month, today.day);

/// The earliest / latest date of birth the picker offers (18–100 years old).
({DateTime min, DateTime max}) dateOfBirthBounds([DateTime? today]) {
  final t = today ?? DateTime.now();
  return (min: _yearsAgo(t, _maxAgeYears), max: _yearsAgo(t, _minAgeYears));
}

/// Date of birth is optional; one entered must be a real date between 18 and 100 years ago.
bool isValidDateOfBirth(DateTime? dob, [DateTime? today]) {
  if (dob == null) return true;
  final b = dateOfBirthBounds(today);
  final d = DateTime(dob.year, dob.month, dob.day);
  return !d.isBefore(b.min) && !d.isAfter(b.max);
}

/// Default session length choices — "custom" asks for minutes.
const coachDurationOptions = <({String value, String label})>[
  (value: '30', label: '30 minutes'),
  (value: '45', label: '45 minutes'),
  (value: '60', label: '1 hour'),
  (value: '90', label: '1.5 hours'),
  (value: '120', label: '2 hours'),
  (value: 'custom', label: 'Custom'),
];

const coachExpertiseLevels = ['Beginner', 'Intermediate', 'Advanced', 'All Levels'];

// ── Coach onboarding (steps 2-4) — the same rules as src/features/coaching/coach-onboarding-validation.ts and the SQL in
// migration 0211. Codes are normalised (trim, strip spaces/dashes, upper-case) BEFORE they are checked.

final _ifscRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
final _panRe = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
final _gstinRe = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
final _upiRe = RegExp(r'^[A-Za-z0-9.\-_]{2,256}@[A-Za-z]{2,64}$');

String _normalizeCode(String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

String normalizeIfsc(String s) => _normalizeCode(s);
String normalizePan(String s) => _normalizeCode(s);
String normalizeGstin(String s) => _normalizeCode(s);

bool isValidIfsc(String s) => _ifscRe.hasMatch(s);
bool isValidPan(String s) => _panRe.hasMatch(s);
bool isValidGstin(String s) => _gstinRe.hasMatch(s);
bool isValidUpi(String s) => _upiRe.hasMatch(s.trim());

/// 9-18 digits, nothing else.
bool isValidAccountNumber(String s) => RegExp(r'^[0-9]{9,18}$').hasMatch(s);

/// A positive whole number of rupees — no decimals, zero or negatives.
bool isValidRupees(String s) => RegExp(r'^[1-9][0-9]{0,8}$').hasMatch(s.trim());

int rupeesToMinor(String s) => int.parse(s.trim()) * 100;

/// "HH:MM" strings; an equal or reversed pair is not a slot.
bool isValidSlot(String start, String end) => start.isNotEmpty && end.isNotEmpty && end.compareTo(start) > 0;

const _dayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// The first repeated or overlapping weekly slot on the same day, as a message naming both slots — or null when there is none.
/// Slots that only touch (ends 12:00, next starts 12:00) are fine. A slot ending at or before its start is ignored here
/// ([isValidSlot] reports it), so it is never reported twice. Same rule as `findAvailabilityConflict` on the web and in migration 0211.
String? findAvailabilityConflict(Iterable<AvailabilityWindow> windows) {
  final slots = [
    for (final w in windows)
      if (isValidSlot(w.startTime.substring(0, 5), w.endTime.substring(0, 5))) (day: w.dayOfWeek, start: w.startTime.substring(0, 5), end: w.endTime.substring(0, 5)),
  ]..sort((a, b) {
      final d = a.day.compareTo(b.day);
      if (d != 0) return d;
      final s = a.start.compareTo(b.start);
      return s != 0 ? s : a.end.compareTo(b.end);
    });
  String label(({int day, String start, String end}) w) => '${_dayShort[w.day]} ${w.start}–${w.end}';
  for (var i = 1; i < slots.length; i++) {
    final prev = slots[i - 1];
    final cur = slots[i];
    if (prev.day != cur.day) continue;
    if (prev.start == cur.start && prev.end == cur.end) return '${label(cur)} is added twice. Remove one of them.';
    if (cur.start.compareTo(prev.end) < 0) return "${label(prev)} overlaps ${label(cur)}. Change one so they don't overlap.";
  }
  return null;
}

const certificateMaxBytes = 5 * 1024 * 1024;

/// The error copy for a certificate upload, or null when it is acceptable (the phone only picks images; PDFs are web-only).
String? validateCertificate(String fileName, int bytes) {
  final n = fileName.toLowerCase();
  final okType = n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.webp') || n.endsWith('.pdf');
  if (!okType) return 'Please choose a JPG, PNG, WEBP or PDF file.';
  if (bytes > certificateMaxBytes) return 'That file is larger than 5MB.';
  return null;
}
