/// Which of the facility's sports the app is showing. `null` is "All Sports" — the default, and what a stale or empty
/// choice falls back to. Otherwise it is the explicit subset the user ticked. Mirrors
/// src/features/facility/sport-selection.ts on the web.
library;

class ResolvedSportSelection {
  const ResolvedSportSelection({required this.ids, required this.isAll});

  /// The sports in view, in the facility's own order. Always at least one once the sport list has loaded.
  final List<String> ids;

  /// Every sport is in view — nothing needs filtering.
  final bool isAll;
}

/// The stored choice checked against the sports the facility actually has: ids that no longer exist drop out, and an
/// empty result means All Sports rather than nothing.
ResolvedSportSelection resolveSportSelection(List<String>? stored, List<String> optionIds) {
  if (stored == null) return ResolvedSportSelection(ids: optionIds, isAll: true);
  final valid = optionIds.where(stored.contains).toList();
  if (valid.isEmpty || valid.length == optionIds.length) return ResolvedSportSelection(ids: optionIds, isAll: true);
  return ResolvedSportSelection(ids: valid, isAll: false);
}

/// Ticks or unticks one sport. The last sport left can't be unticked (there is always something to show), and ticking
/// every sport is the same as "All Sports", stored as `null`.
List<String>? toggleSportSelection(List<String>? stored, List<String> optionIds, String id) {
  final current = resolveSportSelection(stored, optionIds).ids;
  if (current.contains(id)) {
    if (current.length == 1) return stored;
    final next = current.where((x) => x != id).toList();
    return next.length == optionIds.length ? null : next;
  }
  final next = optionIds.where((x) => x == id || current.contains(x)).toList();
  return next.length == optionIds.length ? null : next;
}

/// "All Sports", "Badminton", "Badminton, Cricket", "Badminton +2" — the chip's label.
String sportSelectionLabel(ResolvedSportSelection selection, Map<String, String> names) {
  if (selection.isAll) return 'All Sports';
  final picked = [for (final id in selection.ids) if (names[id] != null) names[id]!];
  if (picked.length <= 2) return picked.join(', ');
  return '${picked.first} +${picked.length - 1}';
}

/// Maintenance, Staff and Inventory look at the whole facility, not one sport: arriving on any page under them puts the
/// selection back to All Sports (and those pages show no sport selector).
bool sportSelectionLocked(String path) => RegExp(r'^/(maintenance|users-roles|inventory)(/|$)').hasMatch(path);
