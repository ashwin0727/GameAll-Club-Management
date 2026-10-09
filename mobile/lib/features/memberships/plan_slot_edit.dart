// The rules for editing one of a plan's slots — pure, so the sheet only draws what this decides.

/// The first thing wrong with an edited slot, or null when it can be saved.
///
/// [enrolled] is how many members are already on the slot: the capacity can't drop below that, or
/// people who already hold a place would be pushed out.
String? validateSlotEdit({
  required List<int> days,
  required String startTime,
  required String endTime,
  required int? capacity,
  required int enrolled,
}) {
  if (days.isEmpty) return 'Select at least one day.';
  if (startTime.compareTo(endTime) >= 0) return 'The end time must be after the start time.';
  if (capacity == null || capacity < 1) return 'Slot capacity must be at least 1.';
  if (capacity < enrolled) {
    return '$enrolled ${enrolled == 1 ? 'member is' : 'members are'} already on this slot — capacity can\'t be lower than that.';
  }
  return null;
}

/// "HH:MM" from a stored time that may carry seconds ("07:00:00").
String clockHm(String time) => time.length >= 5 ? time.substring(0, 5) : time;
