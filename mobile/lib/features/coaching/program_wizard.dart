// Create Coaching Program wizard — the pure rules, mirroring the web's use-program-wizard-form.ts so both
// platforms create the same program: the steps, the choices on each, the program-structure vocabulary per
// sport, and the fee maths. Pure, so it is tested rather than eyeballed.

const programSteps = ['Basic Information', 'Program Details', 'Schedule & Batches', 'Pricing & Settings', 'Review & Create'];

const programAgeGroups = ['4-6', '7-10', '11-14', '15-18', 'Adults', 'All Ages'];
const programSkillLevels = ['Beginner', 'Intermediate', 'Advanced', 'All Levels'];

const programTypes = <({String value, String label, String hint})>[
  (value: 'GROUP', label: 'Group Program', hint: 'Multiple students, shared batches'),
  (value: 'ONE_ON_ONE', label: 'One-on-One', hint: 'Personal, individual coaching'),
  (value: 'TRIAL', label: 'Trial Program', hint: 'A short trial before enrolling'),
];

const sessionDurations = <({String value, String label})>[
  (value: '30', label: '30 minutes'),
  (value: '60', label: '1 Hour'),
  (value: '120', label: '2 Hours'),
  (value: 'custom', label: 'Custom'),
];

const sessionsPerWeekChoices = [1, 2, 3, 4, 5, 6, 7];

/// value = weeks; "custom" lets the owner pick an end date instead.
const programDurations = <({String value, String label})>[
  (value: '4', label: '1 Month (4 Weeks)'),
  (value: '8', label: '2 Months (8 Weeks)'),
  (value: '12', label: '3 Months (12 Weeks)'),
  (value: '24', label: '6 Months (24 Weeks)'),
  (value: '48', label: '12 Months (48 Weeks)'),
  (value: 'custom', label: 'Custom'),
];

const dayLabelsShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const _structureBySport = <String, List<String>>{
  'badminton': ['Basic Techniques', 'Footwork', 'Smash', 'Net Play', 'Drop Shot', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'tennis': ['Forehand', 'Backhand', 'Serve Technique', 'Footwork', 'Volley', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'cricket': ['Batting Technique', 'Bowling Technique', 'Fielding Drills', 'Wicket-Keeping', 'Net Practice', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'football': ['Ball Control', 'Passing & Dribbling', 'Shooting Technique', 'Defensive Drills', 'Set Pieces', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'soccer': ['Ball Control', 'Passing & Dribbling', 'Shooting Technique', 'Defensive Drills', 'Set Pieces', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'basketball': ['Dribbling', 'Shooting Technique', 'Passing', 'Defense Drills', 'Rebounding', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'pickleball': ['Dinking', 'Serve & Return', 'Footwork', 'Net Play', 'Third Shot Drop', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'table tennis': ['Basic Strokes', 'Footwork', 'Spin & Serve', 'Topspin & Backspin', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'squash': ['Basic Strokes', 'Footwork', 'Serve Technique', 'Court Positioning', 'Game Strategy', 'Fitness & Agility', 'Match Practice'],
  'swimming': ['Stroke Technique', 'Breathing Drills', 'Starts & Turns', 'Endurance Building', 'Fitness & Agility', 'Race Practice'],
};
const _genericStructure = ['Basic Techniques', 'Footwork', 'Game Strategy', 'Fitness & Agility', 'Match Practice'];

/// The Program Structure chips for a sport (matched by substring, so "Box Cricket" is cricket); a generic
/// list until a sport is chosen, so the picker is never empty.
List<String> programStructurePresetsForSport(String? sportName) {
  if (sportName == null || sportName.isEmpty) return _genericStructure;
  final lower = sportName.toLowerCase();
  // Longest key first, so "Table Tennis" is table tennis and not tennis.
  final keys = _structureBySport.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (lower.contains(k)) return _structureBySport[k]!;
  }
  return _genericStructure;
}

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `start` plus `weeks` weeks, as an ISO date.
String addWeeksIso(DateTime start, int weeks) => _iso(DateTime(start.year, start.month, start.day + weeks * 7));

/// Weeks the program runs: the chosen preset, or — for "custom" — the start→end span rounded to weeks
/// (0 until the dates make sense).
int weeksInProgram({required String durationWeeks, required DateTime? start, required DateTime? customEnd}) {
  if (durationWeeks != 'custom') return int.tryParse(durationWeeks) ?? 0;
  if (start == null || customEnd == null || customEnd.isBefore(start)) return 0;
  final days = DateTime(customEnd.year, customEnd.month, customEnd.day).difference(DateTime(start.year, start.month, start.day)).inDays;
  final weeks = (days / 7).round();
  return weeks < 1 ? 1 : weeks;
}

/// What the student actually pays, from what was typed. A "per session" fee is multiplied out over every
/// session in the program; discount comes off the base, tax is charged on what is left.
class ProgramFee {
  const ProgramFee({required this.baseInr, required this.discountInr, required this.taxInr, required this.totalInr, required this.totalSessions});
  final num baseInr;
  final num discountInr;
  final num taxInr;
  final num totalInr;
  final int totalSessions;
}

ProgramFee computeProgramFee({
  required num priceInr,
  required bool perSession,
  required int sessionsPerWeek,
  required int weeks,
  num discountInr = 0,
  bool taxApplicable = false,
  num taxPercent = 0,
}) {
  final sessions = sessionsPerWeek * weeks;
  final base = perSession ? priceInr * sessions : priceInr;
  final taxable = base - discountInr;
  final tax = taxApplicable ? ((taxable < 0 ? 0 : taxable) * taxPercent / 100).round() : 0;
  final total = (taxable < 0 ? 0 : taxable) + tax;
  return ProgramFee(baseInr: base, discountInr: discountInr, taxInr: tax, totalInr: total, totalSessions: sessions);
}

/// The one batch a program is created with (a program's schedule is a single day/time/court/coach slot).
class DraftBatch {
  const DraftBatch({
    required this.name,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.courtId,
    this.coachId,
  });
  final String name;
  final List<int> daysOfWeek;
  final String startTime; // HH:MM
  final String endTime;
  final int capacity;
  final String courtId;
  final String? coachId;

  Map<String, dynamic> toPayload() => {
        'courtId': courtId,
        'coachId': coachId,
        'name': name,
        'daysOfWeek': daysOfWeek,
        'startTime': startTime,
        'endTime': endTime,
        'capacity': capacity,
      };
}

/// A batch repeats an existing one when it reuses a name, or the same court + time on an overlapping day.
String? findDuplicateBatch(List<DraftBatch> existing, {required String name, required String courtId, required String startTime, required String endTime, required List<int> days}) {
  final n = name.trim().toLowerCase();
  for (final b in existing) {
    if (b.name.trim().toLowerCase() == n) return 'A batch named "${b.name}" already exists.';
    final sameSlot = b.courtId == courtId && b.startTime == startTime && b.endTime == endTime;
    if (sameSlot && b.daysOfWeek.any(days.contains)) return '"${b.name}" already uses this court, time and day.';
  }
  return null;
}
