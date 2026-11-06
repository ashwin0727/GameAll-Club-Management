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
      return _parse(result);
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
    return Future.wait([for (final v in venues) _fromEnrollAnswer(client, v)]);
  }

  /// One venue's programme (the first that already has a coach, else the first) from its enrolment answer; just the venue card's own
  /// name and price when that answer is not there.
  Future<CoachingListing> _fromEnrollAnswer(
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
        final pick = programs.firstWhere(
          hasCoach,
          orElse: () => programs.first,
        );
        return CoachingListing.fromEnrollProgram(v, pick);
      }
    } on Object {
      // fall through to the card's own name and price
    }
    return fromVenueCards([v]).first;
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
