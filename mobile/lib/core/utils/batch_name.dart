/// A plan's slot is named after the plan plus its time. Slots made before the full range was used carry only the
/// START time ("Morning Monthly Membership (5 AM to 6 AM) — 05:00"); this shows them the way new ones are named
/// ("… — 05:00 to 06:00") so nobody has to guess where the slot ends. Any other name is left alone.
String displayBatchName(String name, String startTime, String endTime) {
  final m = RegExp(r'^(.*?)\s*[—–-]\s*\d{1,2}:\d{2}(?::\d{2})?$').firstMatch(name.trim());
  if (m == null || startTime.length < 5 || endTime.length < 5) return name;
  return '${m.group(1)} — ${startTime.substring(0, 5)} to ${endTime.substring(0, 5)}';
}

/// The name a new slot is created with: the plan's name, then its whole time range.
String newBatchName(String planName, String startTime, String endTime) =>
    '$planName — ${startTime.substring(0, 5)} to ${endTime.substring(0, 5)}';
