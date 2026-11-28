import '../../data/models/coaching.dart';
import 'add_coach_validation.dart';


/// A certificate row being edited.
class CertForm {
  CertForm({required this.id, this.name = '', this.issuer = '', this.year = '', this.path = ''});
  final int id;
  String name;
  String issuer;
  String year;
  String path;
}

const sessionFormatOptions = <({String value, String label, String hint})>[
  (value: 'ONE_TO_ONE', label: '1:1 sessions', hint: 'One coach, one student'),
  (value: 'GROUP', label: 'Group sessions', hint: 'Several students together'),
  (value: 'ASYNC', label: 'Async / video feedback', hint: 'Reviews without a live session'),
];
const sessionDurationOptions = [30, 45, 60, 90, 120];
const languageOptions = ['English', 'Hindi', 'Tamil', 'Telugu', 'Kannada', 'Malayalam', 'Marathi', 'Bengali', 'Gujarati', 'Punjabi'];
const audienceOptions = ['Kids', 'Teens', 'Adults', 'Seniors', 'Beginners', 'Competitive players'];
const timezoneOptions = <({String value, String label})>[
  (value: 'Asia/Kolkata', label: 'India (IST, UTC+5:30)'),
  (value: 'Asia/Dubai', label: 'Dubai (GST, UTC+4)'),
  (value: 'Asia/Singapore', label: 'Singapore (SGT, UTC+8)'),
  (value: 'Europe/London', label: 'London (UK)'),
  (value: 'America/New_York', label: 'New York (US Eastern)'),
  (value: 'Australia/Sydney', label: 'Sydney (AEST)'),
];
const payoutFrequencyOptions = <({String value, String label})>[
  (value: 'WEEKLY', label: 'Weekly'),
  (value: 'BIWEEKLY', label: 'Every 2 weeks'),
  (value: 'MONTHLY', label: 'Monthly'),
];

/// Everything the five onboarding steps edit — pure Dart, so the step rules and the payloads are unit-tested without a widget.
/// Mirrors `OnboardingDraft` / `isStepValid` / `stepPayload` in src/features/coaching/components/use-coach-onboarding.ts.
class CoachOnboardingForm {
  // 1
  bool newPerson = false;
  String userId = '';
  String firstName = '';
  String lastName = '';
  String phone = '';
  String email = '';
  String roleId = '';
  String displayName = '';
  String location = '';
  String timezone = 'Asia/Kolkata';
  final Set<String> languages = {};
  String shortBio = '';
  DateTime? dob;
  // 2
  String niche = '';
  final List<String> subSpecialties = [];
  String experience = '';
  final Set<String> targetAudience = {};
  String methodology = '';
  final List<CertForm> certificates = [];
  final Set<String> sportIds = {};
  final Set<String> expertiseLevels = {};
  // 3
  final Set<String> sessionFormats = {};
  final Set<int> sessionDurations = {};
  String perSessionRate = '';
  String weeklyRate = '';
  String monthlyRate = '';
  // 4
  String entityType = 'INDIVIDUAL';
  String legalName = '';
  String businessAddress = '';
  String taxId = '';
  String payoutMethod = 'BANK_TRANSFER';
  String accountHolderName = '';
  String accountNumber = '';
  String confirmAccountNumber = '';
  String ifsc = '';
  String upiId = '';
  String payoutFrequency = 'MONTHLY';
  String cancellationPolicy = '';
  // 5
  bool agreeTerms = false;
  bool agreeEthics = false;
  bool agreePrivacy = false;
  bool agreeCommission = false;

  int _nextId = 1;
  int nextId() => _nextId++;

  static bool _nonNegative(String s) => s.trim().isEmpty || (RegExp(r'^\d+(\.\d+)?$').hasMatch(s.trim()) && double.parse(s.trim()) >= 0);

  bool get _taxOk => (entityType == 'BUSINESS' && isValidGstin(normalizeGstin(taxId))) || isValidPan(normalizePan(taxId));

  bool _step4Valid(bool hasSavedPayout) {
    if (!(_taxOk || (hasSavedPayout && taxId.trim().isEmpty))) return false;
    if (entityType == 'BUSINESS' && (legalName.trim().isEmpty || businessAddress.trim().isEmpty)) return false;
    if (payoutMethod == 'UPI') return isValidUpi(upiId) || (hasSavedPayout && upiId.trim().isEmpty);
    if (accountHolderName.trim().isEmpty) return false;
    final keepAccount = hasSavedPayout && accountNumber.isEmpty && confirmAccountNumber.isEmpty;
    final accountOk = keepAccount || (isValidAccountNumber(accountNumber) && accountNumber == confirmAccountNumber);
    final ifscOk = isValidIfsc(normalizeIfsc(ifsc)) || (hasSavedPayout && ifsc.trim().isEmpty);
    return accountOk && ifscOk;
  }

  /// One rule-set for both the Next button and the inline errors. [step] is 1..5.
  bool isStepValid(int step, {bool hasSavedPayout = false}) {
    switch (step) {
      case 1:
        if (displayName.trim().isEmpty || !isValidDateOfBirth(dob)) return false;
        if (!newPerson) return userId.isNotEmpty;
        return firstName.trim().isNotEmpty && lastName.trim().isNotEmpty && roleId.isNotEmpty && isValidEmail(email) && phone.length == 10; // the phone number is mandatory: all 10 digits
      case 2:
        return niche.trim().isNotEmpty &&
            sportIds.isNotEmpty &&
            expertiseLevels.isNotEmpty &&
            _nonNegative(experience) &&
            certificates.every((c) => c.name.trim().isNotEmpty);
      case 3:
        return sessionFormats.isNotEmpty &&
            sessionDurations.isNotEmpty &&
            // The three amounts are optional; when one is filled in it has to be a valid whole-rupee amount.
            _optionalRupees(perSessionRate) &&
            _optionalRupees(weeklyRate) &&
            _optionalRupees(monthlyRate);
      case 4:
        return _step4Valid(hasSavedPayout);
      case 5:
        return agreeTerms && agreeEthics && agreePrivacy && agreeCommission;
    }
    return false;
  }

  static String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String? get dobIso => dob == null ? null : _iso(dob!);

  /// The body sent to `save_coach_onboarding_step` for steps 1-4.
  Map<String, dynamic> stepPayload(int step) {
    switch (step) {
      case 1:
        return {
          'displayName': displayName.trim(),
          'location': location.trim(),
          'timezone': timezone,
          'languages': languages.toList(),
          'shortBio': shortBio.trim(),
          'dateOfBirth': dobIso,
        };
      case 2:
        return {
          'niche': niche.trim(),
          'subSpecialties': subSpecialties,
          'experienceYears': experience.trim().isEmpty ? null : double.parse(experience.trim()),
          'targetAudience': targetAudience.toList(),
          'methodology': methodology.trim(),
          'certificates': [
            for (final c in certificates)
              {'name': c.name.trim(), 'issuer': c.issuer.trim(), 'year': int.tryParse(c.year.trim()), 'path': c.path},
          ],
          'sportIds': sportIds.toList(),
          'expertiseLevels': expertiseLevels.toList(),
        };
      case 3:
        final durations = sessionDurations.toList()..sort();
        return {
          'sessionFormats': sessionFormats.toList(),
          'sessionDurations': durations,
          'defaultSessionDurationMinutes': durations.isEmpty ? null : durations.first,
          'perSessionRateMinor': _optionalMinor(perSessionRate),
          'weeklyRateMinor': _optionalMinor(weeklyRate),
          'monthlyRateMinor': _optionalMinor(monthlyRate),
        };
      default:
        final tax = entityType == 'BUSINESS' && isValidGstin(normalizeGstin(taxId)) ? normalizeGstin(taxId) : normalizePan(taxId);
        return {
          'entityType': entityType,
          'legalName': legalName.trim(),
          'businessAddress': businessAddress.trim(),
          'taxId': tax,
          'payoutMethod': payoutMethod,
          'accountHolderName': accountHolderName.trim(),
          'accountNumber': accountNumber.replaceAll(RegExp(r'\s'), ''),
          'ifsc': normalizeIfsc(ifsc),
          'upiId': upiId.trim(),
          'payoutFrequency': payoutFrequency,
          'cancellationPolicy': cancellationPolicy.trim(),
        };
    }
  }

  /// A saved draft back into the form. Secrets never come back (they are masked), so blank secret fields mean "keep".
  static CoachOnboardingForm fromOnboarding(CoachOnboarding o) {
    final f = CoachOnboardingForm()
      ..userId = o.userId
      ..displayName = o.displayName
      ..location = o.location
      ..timezone = o.timezone
      ..shortBio = o.shortBio
      ..dob = o.dateOfBirth == null ? null : DateTime.tryParse(o.dateOfBirth!)
      ..niche = o.niche
      ..experience = o.experienceYears == null ? '' : _trimNum(o.experienceYears!)
      ..methodology = o.methodology
      ..perSessionRate = _rupees(o.perSessionRateMinor)
      ..weeklyRate = _rupees(o.weeklyRateMinor)
      ..monthlyRate = _rupees(o.monthlyRateMinor);
    f.languages.addAll(o.languages);
    f.subSpecialties.addAll(o.subSpecialties);
    f.targetAudience.addAll(o.targetAudience);
    f.sportIds.addAll(o.sportIds);
    f.expertiseLevels.addAll(o.expertiseLevels);
    f.sessionFormats.addAll(o.sessionFormats);
    f.sessionDurations.addAll(o.sessionDurations);
    for (final c in o.certificates) {
      f.certificates.add(CertForm(id: f.nextId(), name: c.name, issuer: c.issuer, year: c.year?.toString() ?? '', path: c.path));
    }
    final p = o.payout;
    if (p != null) {
      f
        ..entityType = p.entityType
        ..legalName = p.legalName ?? ''
        ..businessAddress = p.businessAddress ?? ''
        ..payoutMethod = p.payoutMethod
        ..accountHolderName = p.accountHolderName ?? ''
        ..payoutFrequency = p.payoutFrequency
        ..cancellationPolicy = p.cancellationPolicy ?? '';
    }
    return f;
  }

  static bool _optionalRupees(String s) => s.trim().isEmpty || isValidRupees(s);
  static int? _optionalMinor(String s) => s.trim().isEmpty ? null : rupeesToMinor(s);

  static String _rupees(int? minor) => minor == null ? '' : (minor / 100).round().toString();

  static String _trimNum(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();
}
