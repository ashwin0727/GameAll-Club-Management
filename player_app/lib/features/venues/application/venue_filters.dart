import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/venue.dart';

enum VenueSort {
  recommended('Recommended'),
  name('Name (A - Z)'),
  priceLow('Price: Low to High'),
  priceHigh('Price: High to Low');

  const VenueSort(this.label);
  final String label;
}

enum VenueView { grid, list }

/// Everything the Discover Venues page lets the player narrow the list by. All filtering happens on the list already loaded for the
/// picked city, so changing a filter is instant and never calls the server.
class VenueFilters {
  const VenueFilters({
    this.query = '',
    this.sport,
    this.indoor = false,
    this.outdoor = false,
    this.parking = false,
    this.changingRooms = false,
    this.toilets = false,
    this.cafeteria = false,
    this.equipmentRental = false,
    this.academy = false,
    this.memberships = false,
    this.savedOnly = false,
    this.minPrice,
    this.maxPrice,
    this.sort = VenueSort.recommended,
    this.view = VenueView.grid,
  });

  /// Text typed in the search box (venue name, sport or area).
  final String query;

  /// One sport (as the database spells it, e.g. "Badminton"); null = All Sports.
  final String? sport;

  /// Venue type: neither or both ticked means any; only one ticked keeps just those venues.
  final bool indoor;
  final bool outdoor;

  /// Facilities: each ticked one is required.
  final bool parking;
  final bool changingRooms;
  final bool toilets;
  final bool cafeteria;
  final bool equipmentRental;

  /// Venues that run coaching (academies).
  final bool academy;

  /// Venues that sell memberships.
  final bool memberships;
  final bool savedOnly;

  /// The price range per hour, in rupees; either end null = no limit on that side.
  final int? minPrice;
  final int? maxPrice;
  final VenueSort sort;
  final VenueView view;

  /// How many filters are on (not counting sort and view): shown on the phone's Filters button.
  int get activeCount => [
    if (query.trim().isNotEmpty) 1,
    if (sport != null) 1,
    if (indoor) 1,
    if (outdoor) 1,
    if (parking) 1,
    if (changingRooms) 1,
    if (toilets) 1,
    if (cafeteria) 1,
    if (equipmentRental) 1,
    if (academy) 1,
    if (memberships) 1,
    if (savedOnly) 1,
    if (minPrice != null || maxPrice != null) 1,
  ].length;

  VenueFilters copyWith({
    String? query,
    Object? sport = _keep,
    bool? indoor,
    bool? outdoor,
    bool? parking,
    bool? changingRooms,
    bool? toilets,
    bool? cafeteria,
    bool? equipmentRental,
    bool? academy,
    bool? memberships,
    bool? savedOnly,
    Object? minPrice = _keep,
    Object? maxPrice = _keep,
    VenueSort? sort,
    VenueView? view,
  }) => VenueFilters(
    query: query ?? this.query,
    sport: identical(sport, _keep) ? this.sport : sport as String?,
    indoor: indoor ?? this.indoor,
    outdoor: outdoor ?? this.outdoor,
    parking: parking ?? this.parking,
    changingRooms: changingRooms ?? this.changingRooms,
    toilets: toilets ?? this.toilets,
    cafeteria: cafeteria ?? this.cafeteria,
    equipmentRental: equipmentRental ?? this.equipmentRental,
    academy: academy ?? this.academy,
    memberships: memberships ?? this.memberships,
    savedOnly: savedOnly ?? this.savedOnly,
    minPrice: identical(minPrice, _keep) ? this.minPrice : minPrice as int?,
    maxPrice: identical(maxPrice, _keep) ? this.maxPrice : maxPrice as int?,
    sort: sort ?? this.sort,
    view: view ?? this.view,
  );

  /// "Clear All": every filter off. The chosen sort and view stay as they are.
  VenueFilters cleared() => VenueFilters(sort: sort, view: view);

  static const Object _keep = Object();
}

class VenueFiltersController extends Notifier<VenueFilters> {
  @override
  VenueFilters build() => const VenueFilters();

  void update(VenueFilters Function(VenueFilters f) change) =>
      state = change(state);
  void clear() => state = state.cleared();
}

final venueFiltersProvider =
    NotifierProvider<VenueFiltersController, VenueFilters>(
      VenueFiltersController.new,
    );

/// The sports a venue list can be narrowed to, in the order of the design's chip row. Others found in the data go under "More".
const featuredSports = [
  'Badminton',
  'Football',
  'Cricket',
  'Tennis',
  'Basketball',
  'Pickleball',
  'Padel',
];

/// Every distinct sport in [venues] that is not one of the [featuredSports] chips (case-insensitive), sorted.
List<String> otherSports(List<Venue> venues) {
  final seen = <String, String>{};
  final featured = featuredSports.map((s) => s.toLowerCase()).toSet();
  for (final v in venues) {
    for (final s in v.sports) {
      final key = s.trim().toLowerCase();
      if (key.isEmpty || featured.contains(key)) continue;
      seen.putIfAbsent(key, () => s.trim());
    }
  }
  return seen.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// The most the sliders can reach: the dearest hourly price in the list, rounded up to the next 50.
int priceCeiling(List<Venue> venues) {
  var top = 0;
  for (final v in venues) {
    final p = v.minCourtPriceInr;
    if (p != null && p > top) top = p;
  }
  return top == 0 ? 0 : ((top + 49) ~/ 50) * 50;
}

/// The lowest hourly price in the list, rounded down to the previous 50 (the left end of the price slider).
int priceFloor(List<Venue> venues) {
  int? low;
  for (final v in venues) {
    final p = v.minCourtPriceInr;
    if (p != null && (low == null || p < low)) low = p;
  }
  return low == null ? 0 : (low ~/ 50) * 50;
}

/// How many venues in a list have each thing the Filters panel offers (the "(6)" beside "Indoor").
class FilterCounts {
  const FilterCounts({
    this.indoor = 0,
    this.outdoor = 0,
    this.parking = 0,
    this.changingRooms = 0,
    this.toilets = 0,
    this.cafeteria = 0,
    this.equipmentRental = 0,
    this.academy = 0,
    this.memberships = 0,
  });

  factory FilterCounts.of(List<Venue> venues) {
    int n(bool Function(Venue v) test) => venues.where(test).length;
    return FilterCounts(
      indoor: n((v) => v.venueType == VenueType.indoor),
      outdoor: n((v) => v.venueType == VenueType.outdoor),
      parking: n((v) => v.amenities.parking),
      changingRooms: n((v) => v.amenities.changingRooms),
      toilets: n((v) => v.amenities.toilets),
      cafeteria: n((v) => v.amenities.cafeteria),
      equipmentRental: n((v) => v.amenities.equipmentRental),
      academy: n((v) => v.programCount > 0),
      memberships: n((v) => v.planCount > 0),
    );
  }

  final int indoor;
  final int outdoor;
  final int parking;
  final int changingRooms;
  final int toilets;
  final int cafeteria;
  final int equipmentRental;
  final int academy;
  final int memberships;
}

/// How well a venue is set up for a player, for "Recommended": a photo, more photos, more courts and sports, memberships, coaching and
/// amenities all count. (There are no ratings in the database yet, so this puts the best-presented venues first.)
int recommendedScore(Venue v) {
  var score = 0;
  if (v.heroImageUrl != null) score += 4;
  score += v.photos.length.clamp(0, 4);
  score += v.courtCount.clamp(0, 6);
  score += v.sports.length.clamp(0, 4);
  if (v.planCount > 0) score += 2;
  if (v.programCount > 0) score += 2;
  score += v.amenities.labels.length;
  if (v.minCourtPriceInr != null) score += 1;
  return score;
}

bool _hasSport(Venue v, String sport) =>
    v.sports.any((s) => s.trim().toLowerCase() == sport.trim().toLowerCase());

/// [venues] narrowed and ordered by [f]. [saved] holds the ids of the venues the player has hearted.
List<Venue> applyVenueFilters(
  List<Venue> venues,
  VenueFilters f,
  Set<String> saved,
) {
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
    if (f.sport != null && !_hasSport(v, f.sport!)) return false;
    if (f.indoor != f.outdoor) {
      final want = f.indoor ? VenueType.indoor : VenueType.outdoor;
      if (v.venueType != want) return false;
    }
    final a = v.amenities;
    if (f.parking && !a.parking) return false;
    if (f.changingRooms && !a.changingRooms) return false;
    if (f.toilets && !a.toilets) return false;
    if (f.cafeteria && !a.cafeteria) return false;
    if (f.equipmentRental && !a.equipmentRental) return false;
    if (f.academy && v.programCount == 0) return false;
    if (f.memberships && v.planCount == 0) return false;
    if (f.savedOnly && !saved.contains(v.id)) return false;
    if (f.maxPrice != null || f.minPrice != null) {
      final p = v.minCourtPriceInr;
      if (p == null) return false;
      if (f.maxPrice != null && p > f.maxPrice!) return false;
      if (f.minPrice != null && p < f.minPrice!) return false;
    }
    return true;
  }).toList();

  int byName(Venue a, Venue b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  out.sort((a, b) {
    if (f.sort == VenueSort.name) return byName(a, b);
    if (f.sort == VenueSort.recommended) {
      final c = recommendedScore(b).compareTo(recommendedScore(a));
      return c != 0 ? c : byName(a, b);
    }
    final pa = a.minCourtPriceInr;
    final pb = b.minCourtPriceInr;
    // venues without a price go last either way
    if (pa == null && pb == null) return byName(a, b);
    if (pa == null) return 1;
    if (pb == null) return -1;
    final c = f.sort == VenueSort.priceLow
        ? pa.compareTo(pb)
        : pb.compareTo(pa);
    return c != 0 ? c : byName(a, b);
  });
  return out;
}

// ── Saved venues (the heart on a card) ─────────────────────────────────────

/// The venues the player has hearted, kept on this device so they are still there after a reload.
class SavedVenuesController extends Notifier<Set<String>> {
  static const _key = 'saved_venue_ids';

  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_key);
      if (ids != null && ids.isNotEmpty) state = {...state, ...ids};
    } catch (_) {
      // storage is blocked (private window): hearts just last for this visit
    }
  }

  Future<void> toggle(String venueId) async {
    final next = {...state};
    if (!next.remove(venueId)) next.add(venueId);
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, next.toList());
    } catch (_) {}
  }
}

final savedVenuesProvider =
    NotifierProvider<SavedVenuesController, Set<String>>(
      SavedVenuesController.new,
    );
