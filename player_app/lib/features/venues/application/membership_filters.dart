import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/venue.dart';
import 'venue_filters.dart';

/// The four lengths a membership is sold in. A plan belongs to the length its days are closest to (a month is about 30 days, a year about
/// 365); a plan of some other length (a 10-day pass) is none of them and is left out of the price tiles.
enum PlanDuration {
  monthly('Monthly'),
  threeMonths('3 Months'),
  sixMonths('6 Months'),
  yearly('Yearly');

  const PlanDuration(this.label);
  final String label;

  static PlanDuration? ofDays(int days) {
    if (days >= 25 && days <= 45) return monthly;
    if (days >= 80 && days <= 100) return threeMonths;
    if (days >= 170 && days <= 200) return sixMonths;
    if (days >= 350 && days <= 380) return yearly;
    return null;
  }
}

/// "Time Slot" in the filters: the venue is open at some point in this part of the day.
enum TimeSlot {
  any('Any Time', 0, 24),
  morning('Morning (5 AM – 12 PM)', 5, 12),
  afternoon('Afternoon (12 – 5 PM)', 12, 17),
  evening('Evening (5 – 10 PM)', 17, 22);

  const TimeSlot(this.label, this.fromHour, this.toHour);
  final String label;
  final int fromHour;
  final int toHour;
}

/// "Days" in the filters: the venue has membership batches on all of these weekdays (0 = Sunday ... 6 = Saturday).
enum DayCover {
  monFri('Mon – Fri', {1, 2, 3, 4, 5}),
  monSat('Mon – Sat', {1, 2, 3, 4, 5, 6}),
  allDays('All Days', {0, 1, 2, 3, 4, 5, 6});

  const DayCover(this.label, this.days);
  final String label;
  final Set<int> days;
}

/// The lowest price of each length a venue sells, in rupees.
Map<PlanDuration, int> lowestPriceByDuration(Venue v) {
  final out = <PlanDuration, int>{};
  for (final p in v.planPrices) {
    final d = PlanDuration.ofDays(p.durationDays);
    if (d == null || p.priceInr <= 0) continue;
    final cur = out[d];
    if (cur == null || p.priceInr < cur) out[d] = p.priceInr;
  }
  return out;
}

/// The lowest price among every active plan of the venue (any length), or null when it has none.
int? lowestPlanPrice(Venue v) {
  final tiers = lowestPriceByDuration(v).values;
  if (tiers.isNotEmpty) return tiers.reduce((a, b) => a < b ? a : b);
  return v.minPlanPriceInr;
}

/// Everything the Memberships page lets the player narrow the list by. Like the Venues page, all of it works on the list already loaded
/// for the picked city.
class MembershipFilters {
  const MembershipFilters({
    this.query = '',
    this.sport,
    this.durations = const {},
    this.slot = TimeSlot.any,
    this.days = const {},
    this.view = VenueView.list,
  });

  final String query;
  final String? sport;

  /// Ticked lengths: a venue stays if it sells any of them. None ticked = any.
  final Set<PlanDuration> durations;
  final TimeSlot slot;

  /// Ticked day groups: a venue stays if it covers any of them. None ticked = any.
  final Set<DayCover> days;
  final VenueView view;

  int get activeCount => [
    if (query.trim().isNotEmpty) 1,
    if (sport != null) 1,
    ...durations.map((_) => 1),
    if (slot != TimeSlot.any) 1,
    ...days.map((_) => 1),
  ].length;

  MembershipFilters copyWith({
    String? query,
    Object? sport = _keep,
    Set<PlanDuration>? durations,
    TimeSlot? slot,
    Set<DayCover>? days,
    VenueView? view,
  }) => MembershipFilters(
    query: query ?? this.query,
    sport: identical(sport, _keep) ? this.sport : sport as String?,
    durations: durations ?? this.durations,
    slot: slot ?? this.slot,
    days: days ?? this.days,
    view: view ?? this.view,
  );

  /// Clear All: every filter off; the grid / list choice stays.
  MembershipFilters cleared() => MembershipFilters(view: view);

  static const Object _keep = Object();
}

class MembershipFiltersController extends Notifier<MembershipFilters> {
  @override
  MembershipFilters build() => const MembershipFilters();

  void update(MembershipFilters Function(MembershipFilters f) change) =>
      state = change(state);
  void clear() => state = state.cleared();
}

final membershipFiltersProvider =
    NotifierProvider<MembershipFiltersController, MembershipFilters>(
      MembershipFiltersController.new,
    );

bool _opensDuring(Venue v, TimeSlot slot) {
  if (slot == TimeSlot.any) return true;
  if (v.open24h && v.opens == null) return true;
  final from = _hour(v.opens);
  final to = _hour(v.closes);
  if (from == null || to == null) return false;
  return from < slot.toHour && to > slot.fromHour;
}

double? _hour(String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.first);
  if (h == null) return null;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return h + m / 60;
}

/// How many venues in [venues] have each length / day group (the "(12)" beside "Monthly").
({Map<PlanDuration, int> durations, Map<DayCover, int> days}) membershipCounts(
  List<Venue> venues,
) {
  final d = {for (final x in PlanDuration.values) x: 0};
  final c = {for (final x in DayCover.values) x: 0};
  for (final v in venues) {
    for (final k in lowestPriceByDuration(v).keys) {
      d[k] = d[k]! + 1;
    }
    for (final k in DayCover.values) {
      if (v.membershipDays.containsAll(k.days)) c[k] = c[k]! + 1;
    }
  }
  return (durations: d, days: c);
}

/// [venues] narrowed by [f], best presented first (like the Venues page's Recommended order).
List<Venue> applyMembershipFilters(List<Venue> venues, MembershipFilters f) {
  final q = f.query.trim().toLowerCase();
  final out = venues.where((v) {
    if (q.isNotEmpty) {
      final haystack = [
        v.name,
        v.area ?? '',
        v.city,
        ...v.sports,
      ].join(' ').toLowerCase();
      if (!q.split(RegExp(r'\s+')).every(haystack.contains)) return false;
    }
    if (f.sport != null &&
        !v.sports.any(
          (s) => s.trim().toLowerCase() == f.sport!.trim().toLowerCase(),
        )) {
      return false;
    }
    if (f.durations.isNotEmpty) {
      final have = lowestPriceByDuration(v).keys.toSet();
      if (f.durations.intersection(have).isEmpty) return false;
    }
    if (!_opensDuring(v, f.slot)) return false;
    if (f.days.isNotEmpty &&
        !f.days.any((g) => v.membershipDays.containsAll(g.days))) {
      return false;
    }
    return true;
  }).toList();

  int byName(Venue a, Venue b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  out.sort((a, b) {
    final c = recommendedScore(b).compareTo(recommendedScore(a));
    return c != 0 ? c : byName(a, b);
  });
  return out;
}
