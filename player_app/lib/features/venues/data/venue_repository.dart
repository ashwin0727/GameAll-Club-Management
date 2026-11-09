import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/coaching_listing.dart';
import '../domain/venue.dart';
import '../domain/venue_detail.dart';

/// Where the venue list comes from. The Supabase version is the real one; tests supply a fake.
abstract class VenueRepository {
  /// The venues for a picked location such as "Bangalore, Karnataka" (empty when there are none): all bookable venues, only those
  /// with membership plans, or only those with coaching programmes, depending on [kind].
  Future<List<Venue>> listForLocation(
    String location, {
    VenueKind kind = VenueKind.venues,
  });

  /// The coaching programmes in a picked location, each with its venue and coach. The default builds them from the venue list (a name
  /// and the venue's lowest price only), which is what the older database gives; the Supabase version asks for the full list first.
  Future<List<CoachingListing>> listCoaching(String location) async {
    final venues = await listForLocation(location, kind: VenueKind.coaching);
    return fromVenueCards(venues);
  }

  /// Where each venue is (venue id -> latitude, longitude), for "nearest first". Empty when the database does not give positions.
  Future<Map<String, (double, double)>> venueCoords(String location) async =>
      const {};

  /// One venue's full page, or null when it does not exist or is not open.
  Future<VenueDetail?> getVenue(String venueId) async => null;

  /// The hourly slots of each of a sport's courts on a day.
  Future<List<CourtSlots>> availability(AvailabilityQuery query) async =>
      const [];
}

/// Calls the public `list_public_venue_cards` database function (migration 0171). It needs no sign-in: anyone can look at venues.
class SupabaseVenueRepository implements VenueRepository {
  SupabaseVenueRepository([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<List<Venue>> listForLocation(
    String location, {
    VenueKind kind = VenueKind.venues,
  }) async {
    final client = _client;
    if (client == null) return const [];
    final place = splitLocation(location);
    final params = {'p_city': place.city, 'p_state': place.state};
    try {
      final result = await client.rpc(
        'list_public_venue_cards',
        params: {...params, 'p_kind': kind.wire},
      );
      final venues = _parse(result);
      if (kind != VenueKind.memberships) return venues;
      // Migration 0178 (prices per length and per sport) may not be installed: then each venue's own enrolment answer has them.
      return await Future.wait([
        for (final v in venues) _withPlanPrices(client, v),
      ]);
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
    }
    // Migration 0171 is not installed yet: the older list still answers for plain venues (no pictures or prices); the other kinds are empty.
    if (kind != VenueKind.venues) return const [];
    try {
      return _parse(await client.rpc('list_public_venues', params: params));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return const [];
      rethrow;
    }
  }

  @override
  Future<List<CoachingListing>> listCoaching(String location) async {
    final client = _client;
    if (client == null) return const [];
    final place = splitLocation(location);
    try {
      final result = await client.rpc(
        'list_public_coaching_programs',
        params: {'p_city': place.city, 'p_state': place.state},
      );
      return [
        for (final e in (result as List<dynamic>? ?? const []))
          if (e is Map) CoachingListing.fromJson(e.cast<String, dynamic>()),
      ];
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
    }
    // Migration 0179 is not installed yet. The venue list still knows which venues have coaching, and each venue's own enrolment answer
    // (migration 0176) has its programmes with description, level, batches and coach: take one programme per venue from that.
    final venues = await listForLocation(location, kind: VenueKind.coaching);
    final lists = await Future.wait([
      for (final v in venues) _fromEnrollAnswer(client, v),
    ]);
    return [for (final l in lists) ...l];
  }

  /// [v] with its plans (length and price) and the plans each sport has, read from the venue's enrolment answer
  /// (`get_public_membership_enroll`, migration 0175) when the list did not carry them.
  Future<Venue> _withPlanPrices(SupabaseClient client, Venue v) async {
    if (v.planPrices.isNotEmpty) return v;
    try {
      final r = await client.rpc(
        'get_public_membership_enroll',
        params: {'p_facility_id': v.id},
      );
      if (r is! Map) return v;
      final prices = <String, PlanPrice>{};
      for (final p in (r['plans'] as List<dynamic>? ?? const [])) {
        if (p is Map &&
            p['id'] is String &&
            p['priceInr'] is num &&
            p['durationDays'] is num) {
          prices[p['id'] as String] = PlanPrice(
            (p['durationDays'] as num).toInt(),
            (p['priceInr'] as num).toInt(),
          );
        }
      }
      if (prices.isEmpty) return v;
      // a plan belongs to a sport through the batches behind the time slots
      final bySport = <String, Map<String, PlanPrice>>{};
      for (final s in (r['slots'] as List<dynamic>? ?? const [])) {
        if (s is! Map || s['sportName'] is! String) continue;
        for (final b in (s['batches'] as List<dynamic>? ?? const [])) {
          final plan = b is Map ? prices[b['planId']] : null;
          if (plan != null) {
            (bySport[s['sportName'] as String] ??= {})[b['planId'] as String] =
                plan;
          }
        }
      }
      return v.withPlans(prices.values.toList(), {
        for (final e in bySport.entries) e.key: e.value.values.toList(),
      });
    } on Object {
      return v;
    }
  }

  /// One venue's programmes from its enrolment answer: for each sport, the first programme that already has a coach (else the first);
  /// just the venue card's own name and price when that answer is not there.
  Future<List<CoachingListing>> _fromEnrollAnswer(
    SupabaseClient client,
    Venue v,
  ) async {
    try {
      final r = await client.rpc(
        'get_public_coaching_enroll',
        params: {'p_facility_id': v.id},
      );
      final programs = [
        for (final p
            in ((r is Map ? r['programs'] : null) as List<dynamic>? ??
                const []))
          if (p is Map) p.cast<String, dynamic>(),
      ];
      if (programs.isNotEmpty) {
        bool hasCoach(Map<String, dynamic> p) => [
          for (final b in (p['batches'] as List<dynamic>? ?? const []))
            if (b is Map && b['coach'] is Map) b,
        ].isNotEmpty;
        final bySport = <String, List<Map<String, dynamic>>>{};
        for (final p in programs) {
          (bySport[(p['sportName'] as String?)?.toLowerCase() ?? ''] ??= [])
              .add(p);
        }
        return [
          for (final group in bySport.values)
            CoachingListing.fromEnrollProgram(
              v,
              group.firstWhere(hasCoach, orElse: () => group.first),
            ),
        ];
      }
    } on Object {
      // fall through to the card's own name and price
    }
    return fromVenueCards([v]);
  }

  @override
  Future<VenueDetail?> getVenue(String venueId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final result = await client.rpc(
        'get_public_venue',
        params: {'p_facility_id': venueId},
      );
      if (result == null) return null;
      return VenueDetail.fromJson((result as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      // migration 0174 is not installed yet: the venue page cannot open, which reads as "venue not found"
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, (double, double)>> venueCoords(String location) async {
    final client = _client;
    if (client == null) return const {};
    final place = splitLocation(location);
    try {
      final result = await client.rpc(
        'list_public_venue_coords',
        params: {'p_city': place.city, 'p_state': place.state},
      );
      return {
        for (final e in (result as List<dynamic>? ?? const []))
          if (e is Map && e['id'] is String && e['lat'] is num && e['lng'] is num)
            e['id'] as String: (
              (e['lat'] as num).toDouble(),
              (e['lng'] as num).toDouble(),
            ),
      };
    } catch (_) {
      // migration 0186 not applied, or offline: no distances, the usual order
      return const {};
    }
  }

  @override
  Future<List<CourtSlots>> availability(AvailabilityQuery query) async {
    final client = _client;
    if (client == null) return const [];
    final result = await client.rpc(
      'get_public_court_availability',
      params: {
        'p_facility_id': query.venueId,
        'p_facility_sport_id': query.sportId,
        'p_date': query.dayKey,
      },
    );
    return [
      for (final c in (result as List<dynamic>))
        CourtSlots.fromJson((c as Map).cast<String, dynamic>()),
    ];
  }

  List<Venue> _parse(dynamic result) => [
    for (final v in (result as List<dynamic>))
      Venue.fromJson((v as Map).cast<String, dynamic>()),
  ];
}

/// One listing per venue, from the venue cards alone: the first programme name and the venue's lowest price (no coach, no description).
List<CoachingListing> fromVenueCards(List<Venue> venues) => [
  for (final v in venues)
    CoachingListing.fromVenueCard(
      v,
      v.programNames.isEmpty ? 'Coaching' : v.programNames.first,
    ),
];
