// The Create Plan wizard's rules — a port of src/features/memberships/create-plan-wizard.ts (and the
// label helpers in plan-insights.ts) so the web and the app validate, label and save a plan the same
// way. Pure Dart: the screen only draws what this decides.

/// 0-based step index → title and the short label under its circle.
const planWizardSteps = <({String title, String label})>[
  (title: 'Plan Details', label: 'Basic Info'),
  (title: 'Plan Configuration', label: 'Pricing'),
  (title: 'Court Access', label: 'Court Access'),
  (title: 'Review & Create', label: 'Review'),
];

/// Fixed duration presets, in days — "Custom" lets the owner type any other length of months. Used
/// for a time-based plan's Duration and a recurring plan's Billing Interval alike (it is the same
/// `durationDays` either way).
const durationPresets = <({String label, int? days})>[
  (label: '1 Month', days: 30),
  (label: '3 Months', days: 90),
  (label: '6 Months', days: 180),
  (label: '1 Year', days: 365),
  (label: 'Custom', days: null),
];

const planCategories = [
  'Regular Membership',
  'Premium Membership',
  'Student Membership',
  'Corporate Membership',
  'Other',
];

/// Court time slots aren't capacity-limited anywhere in the booking engine, so every slot a plan
/// creates gets this generously high placeholder instead of an artificial 1-member cap.
const unlimitedWindowCapacity = 999;

/// Weekday labels, 0 = Sunday … 6 = Saturday (the database's numbering).
const planDayAbbr = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// One recurring slot the plan reserves — becomes a real session batch once the plan exists.
class PlanTimeWindow {
  PlanTimeWindow({
    required this.id,
    required this.courtId,
    required this.daysOfWeek,
    this.startTime = '07:00',
    this.endTime = '08:00',
    this.capacity = unlimitedWindowCapacity,
  });

  /// A local key only, so added / removed slots can be tracked before any of them are real rows.
  final String id;
  String courtId;
  List<int> daysOfWeek;
  String startTime; // "HH:MM"
  String endTime;
  int capacity;
}

class PlanWizardDraft {
  String name = '';
  String description = '';
  String planType = 'TIME_BASED'; // TIME_BASED | RECURRING
  String category = planCategories.first;
  int priceInr = 0;
  int durationDays = 30;

  /// 0 means "not set" — saved as nothing, same as an empty field.
  int joiningFeeInr = 0;
  int securityDepositInr = 0;

  /// `badgeText` is kept while `showBadge` is off, so switching it back on restores what was typed.
  bool showBadge = true;
  String badgeText = 'Popular';

  /// Which courts the plan can reserve time on; a time window's own court must be one of these.
  List<String> courtIds = [];

  /// The day set a newly added time window starts with (each window then carries its own days).
  List<int> playingDays = [1, 2, 3, 4, 5];
  List<PlanTimeWindow> timeWindows = [];

  /// Booking preferences shown for the owner's reference. Like the web, they are not saved — there is
  /// no enforcement for either in the booking engine yet.
  bool allowAdvanceBooking = true;
  bool limitConsecutiveSlots = false;
  List<String> features = [];

  bool get isRecurring => planType == 'RECURRING';
}

/// Every field's own error for [step] (0-based), keyed by field name.
Map<String, String> planFieldErrors(int step, PlanWizardDraft d) {
  final errors = <String, String>{};
  if (step == 0) {
    if (d.name.trim().isEmpty) errors['name'] = 'Plan name is required.';
    if (d.description.length > 200) errors['description'] = "Description can't be more than 200 characters.";
  }
  if (step == 1) {
    if (d.priceInr <= 0) errors['priceInr'] = 'Price must be greater than 0.';
    if (d.durationDays <= 0) errors['durationDays'] = 'Duration must be at least 1 day.';
    if (d.joiningFeeInr < 0) errors['joiningFeeInr'] = "Joining fee can't be negative.";
    if (d.securityDepositInr < 0) errors['securityDepositInr'] = "Security deposit can't be negative.";
  }
  if (step == 2) {
    if (d.courtIds.isEmpty) errors['courtIds'] = 'Select at least one court.';
    if (d.playingDays.isEmpty) errors['playingDays'] = 'Select at least one playing day.';
    if (d.timeWindows.isEmpty) errors['timeWindows'] = 'Add at least one time window.';
    final invalid = d.timeWindows.any((w) => w.startTime.compareTo(w.endTime) >= 0 || w.capacity <= 0);
    if (invalid) {
      errors['timeWindows'] = 'Every time window needs an end time after its start time and a capacity of at least 1.';
    }
    if (d.timeWindows.any((w) => w.daysOfWeek.isEmpty)) {
      errors['timeWindows'] = 'Every time slot needs at least one day.';
    }
  }
  return errors;
}

/// The first error on [step], or null when the step is complete.
String? validatePlanStep(int step, PlanWizardDraft d) {
  final errors = planFieldErrors(step, d);
  return errors.isEmpty ? null : errors.values.first;
}

/// The furthest step reachable — a step only opens once everything before it is valid. Review has
/// nothing of its own to require, so it opens as soon as steps 1–3 are filled in.
int furthestReachablePlanStep(PlanWizardDraft d) {
  for (var step = 0; step <= 2; step++) {
    if (validatePlanStep(step, d) != null) return step;
  }
  return 3;
}

/// Two slots double-book a court when it is the same court, on a shared weekday, at overlapping
/// times. Informational only — courts may share capacity, so this warns rather than blocks.
bool windowsOverlap(PlanTimeWindow a, PlanTimeWindow b) {
  if (a.courtId != b.courtId) return false;
  if (!a.daysOfWeek.any(b.daysOfWeek.contains)) return false;
  return a.startTime.compareTo(b.endTime) < 0 && b.startTime.compareTo(a.endTime) < 0;
}

/// The first *other* slot [target] overlaps, if any.
PlanTimeWindow? findOverlap(List<PlanTimeWindow> windows, PlanTimeWindow target) {
  for (final w in windows) {
    if (w.id != target.id && windowsOverlap(w, target)) return w;
  }
  return null;
}

/// The feature list actually saved: trimmed, blanks dropped.
List<String> composePlanFeatures(PlanWizardDraft d) => d.features.map((f) => f.trim()).where((f) => f.isNotEmpty).toList();

int planMonths(int durationDays) {
  final m = (durationDays / 30).round();
  return m < 1 ? 1 : m;
}

/// "1 Month", "3 Months", "12 Months" — the web's own duration wording.
String planWizardDurationLabel(int durationDays) {
  final m = planMonths(durationDays);
  return m == 1 ? '1 Month' : '$m Months';
}

/// "every month", "every 3 months".
String planBillingIntervalLabel(int durationDays) {
  final m = planMonths(durationDays);
  return m == 1 ? 'every month' : 'every $m months';
}

/// The unit after the price in the review: "month", or "3 months" etc.
String planPriceUnit(int durationDays) =>
    planMonths(durationDays) == 1 ? 'month' : planWizardDurationLabel(durationDays).toLowerCase();

/// A draft key for a new time window.
int _windowSeq = 0;
String newPlanWindowId() {
  _windowSeq += 1;
  return 'w-${DateTime.now().microsecondsSinceEpoch}-$_windowSeq';
}
