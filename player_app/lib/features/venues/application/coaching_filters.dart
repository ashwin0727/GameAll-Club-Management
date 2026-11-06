import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/coaching_listing.dart';
import 'membership_filters.dart' show TimeSlot;
import 'venue_filters.dart' show VenueView;

/// The three levels the filter offers (a programme for "All Levels" matches every one of them).
enum CoachingLevel {
  beginner('Beginner'),
  intermediate('Intermediate'),
  advanced('Advanced');

  const CoachingLevel(this.label);
  final String label;
}

/// "Coaching Type": group batches or one-to-one lessons.
enum CoachingType {
  group('Group Training', 'GROUP'),
  individual('Individual Training', 'ONE_ON_ONE');

  const CoachingType(this.label, this.wire);
  final String label;
  final String wire;
}

/// "Days": any batch of the programme runs on weekdays, or on the weekend.
enum DaysPick {
  any('Any Days'),
  weekdays('Weekdays (Mon – Fri)'),
  weekends('Weekends (Sat – Sun)');

  const DaysPick(this.label);
  final String label;
}

/// Everything the Coaching page lets the player narrow the list by. Works on the list already loaded for the picked city.
class CoachingFilters {
  const CoachingFilters({
    this.query = '',
    this.sport,
    this.levels = const {},
    this.types = const {},
    this.time = TimeSlot.any,
    this.days = DaysPick.any,
    this.view = VenueView.grid,
  });

  final String query;
  final String? sport;
  final Set<CoachingLevel> levels;
  final Set<CoachingType> types;
  final TimeSlot time;
  final DaysPick days;
  final VenueView view;

  int get activeCount => [
    if (query.trim().isNotEmpty) 1,
    if (sport != null) 1,
    ...levels.map((_) => 1),
    ...types.map((_) => 1),
    if (time != TimeSlot.any) 1,
    if (days != DaysPick.any) 1,
  ].length;

  CoachingFilters copyWith({
    String? query,
    Object? sport = _keep,
    Set<CoachingLevel>? levels,
    Set<CoachingType>? types,
    TimeSlot? time,
    DaysPick? days,
    VenueView? view,
  }) => CoachingFilters(
    query: query ?? this.query,
    sport: identical(sport, _keep) ? this.sport : sport as String?,
    levels: levels ?? this.levels,
    types: types ?? this.types,
    time: time ?? this.time,
    days: days ?? this.days,
    view: view ?? this.view,
  );

  CoachingFilters cleared() => CoachingFilters(view: view);

  static const Object _keep = Object();
}

class CoachingFiltersController extends Notifier<CoachingFilters> {
  @override
  CoachingFilters build() => const CoachingFilters();

  void update(CoachingFilters Function(CoachingFilters f) change) =>
      state = change(state);
  void clear() => state = state.cleared();
}

final coachingFiltersProvider =
    NotifierProvider<CoachingFiltersController, CoachingFilters>(
      CoachingFiltersController.new,
    );

CoachingLevel? levelOf(String level) {
  final l = level.trim().toLowerCase();
  for (final x in CoachingLevel.values) {
    if (x.label.toLowerCase() == l) return x;
  }
  return null;
}

bool _matchesLevel(CoachingListing p, Set<CoachingLevel> levels) {
  if (levels.isEmpty) return true;
  final own = levelOf(p.level);
  return own == null || levels.contains(own);
}

bool _matchesTime(CoachingListing p, TimeSlot t) {
  if (t == TimeSlot.any) return true;
  return p.batches.any((b) => b.startHour >= t.fromHour && b.startHour < t.toHour);
}

bool _matchesDays(CoachingListing p, DaysPick d) {
  if (d == DaysPick.any) return true;
  final want = d == DaysPick.weekdays ? const {1, 2, 3, 4, 5} : const {0, 6};
  return p.batches.any((b) => b.days.any(want.contains));
}

/// How many programmes in [all] each level and type tick would keep (the "(4)" beside "Beginner").
({Map<CoachingLevel, int> levels, Map<CoachingType, int> types}) coachingCounts(
  List<CoachingListing> all,
) {
  final l = {for (final x in CoachingLevel.values) x: 0};
  final t = {for (final x in CoachingType.values) x: 0};
  for (final p in all) {
    final own = levelOf(p.level);
    for (final x in CoachingLevel.values) {
      if (own == null || own == x) l[x] = l[x]! + 1;
    }
    for (final x in CoachingType.values) {
      if (p.programType == x.wire) t[x] = t[x]! + 1;
    }
  }
  return (levels: l, types: t);
}

/// The sports that appear in [all], A to Z.
List<String> coachingSports(List<CoachingListing> all) {
  final seen = <String, String>{};
  for (final p in all) {
    final s = p.sport?.trim();
    if (s != null && s.isNotEmpty) seen.putIfAbsent(s.toLowerCase(), () => s);
  }
  return seen.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// [all] narrowed by [f]; programmes with a coach (and more of the card filled in) come first.
List<CoachingListing> applyCoachingFilters(
  List<CoachingListing> all,
  CoachingFilters f,
) {
  final q = f.query.trim().toLowerCase();
  final out = all.where((p) {
    if (q.isNotEmpty) {
      final haystack = [
        p.name,
        p.venueName,
        p.venuePlace,
        p.sport ?? '',
        p.coach?.name ?? '',
        p.level,
      ].join(' ').toLowerCase();
      if (!q.split(RegExp(r'\s+')).every(haystack.contains)) return false;
    }
    if (f.sport != null &&
        (p.sport ?? '').trim().toLowerCase() != f.sport!.trim().toLowerCase()) {
      return false;
    }
    if (!_matchesLevel(p, f.levels)) return false;
    if (f.types.isNotEmpty && !f.types.any((t) => t.wire == p.programType)) {
      return false;
    }
    return _matchesTime(p, f.time) && _matchesDays(p, f.days);
  }).toList();

  out.sort((a, b) {
    final c = _score(b).compareTo(_score(a));
    if (c != 0) return c;
    final v = a.venueName.toLowerCase().compareTo(b.venueName.toLowerCase());
    return v != 0 ? v : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

/// A programme with a coach, a rating, a description and a venue photo is better presented than one without.
int _score(CoachingListing p) =>
    (p.coach != null ? 4 : 0) +
    (p.coach?.avatarUrl != null ? 1 : 0) +
    (p.coach?.ratingLabel != null ? 1 : 0) +
    (p.description != null ? 2 : 0) +
    (p.venueImage != null ? 2 : 0) +
    (p.batches.isNotEmpty ? 1 : 0);
