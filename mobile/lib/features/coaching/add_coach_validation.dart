// Validation for the Add Coach form's "+ New person" fields — the same rules as the web's add-coach-validation.ts,
// pure so they are tested rather than eyeballed.

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
