import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player_home/application/player_home_controller.dart';
import '../../player_home/data/device_location.dart';
import '../../auth/application/auth_providers.dart';
import '../data/coaching_enroll_repository.dart';
import '../data/membership_enroll_repository.dart';
import '../data/venue_repository.dart';
import '../domain/coaching_enroll.dart';
import '../domain/coaching_listing.dart';
import '../domain/membership_enroll.dart';
import '../domain/venue.dart';
import '../domain/venue_detail.dart';

/// The data source. Tests override this with a fake.
final venueRepositoryProvider = Provider<VenueRepository>(
  (ref) => SupabaseVenueRepository(),
);

/// The venues for the city the player picked, for one kind of page (all venues, those with membership plans, those with coaching).
/// Picking another city loads that city's list by itself.
final venuesForSelectedCityProvider = FutureProvider.autoDispose
    .family<List<Venue>, VenueKind>((ref, kind) {
      final location = ref.watch(selectedCityProvider);
      return ref
          .watch(venueRepositoryProvider)
          .listForLocation(location, kind: kind);
    });

/// One venue's page.
final venueDetailProvider = FutureProvider.autoDispose
    .family<VenueDetail?, String>(
      (ref, id) => ref.watch(venueRepositoryProvider).getVenue(id),
      retry: (_, _) => null,
    );

/// The slots of a venue's courts for one sport on one day.
final courtSlotsProvider = FutureProvider.autoDispose
    .family<List<CourtSlots>, AvailabilityQuery>(
      (ref, q) => ref.watch(venueRepositoryProvider).availability(q),
      retry: (_, _) => null,
    );

/// The Enroll Membership page's data source. Tests override this with a fake.
final membershipEnrollRepositoryProvider = Provider<MembershipEnrollRepository>(
  (ref) => SupabaseMembershipEnrollRepository(),
);

/// A venue's time slots and plans for joining a membership.
final enrollInfoProvider = FutureProvider.autoDispose
    .family<EnrollInfo?, String>(
      (ref, id) => ref.watch(membershipEnrollRepositoryProvider).info(id),
      retry: (_, _) => null,
    );

/// The memberships the signed-in player already has at a venue (empty when signed out).
final myMembershipsAtProvider = FutureProvider.autoDispose
    .family<List<ExistingMembership>, String>((ref, id) {
      if (ref.watch(currentPlayerProvider) == null) return const [];
      return ref.watch(membershipEnrollRepositoryProvider).myMemberships(id);
    });

/// The Coaching page's data source. Tests override this with a fake.
final coachingEnrollRepositoryProvider = Provider<CoachingEnrollRepository>(
  (ref) => SupabaseCoachingEnrollRepository(),
);

/// A venue's coaching programmes (with batches, coaches and fees).
final coachingInfoProvider = FutureProvider.autoDispose
    .family<CoachingInfo?, String>(
      (ref, id) => ref.watch(coachingEnrollRepositoryProvider).info(id),
      retry: (_, _) => null,
    );

/// The coaching enrolments the signed-in player already has at a venue (empty when signed out).
final myCoachingAtProvider = FutureProvider.autoDispose
    .family<List<MyCoaching>, String>((ref, id) {
      if (ref.watch(currentPlayerProvider) == null) return const [];
      return ref.watch(coachingEnrollRepositoryProvider).mine(id);
    });

/// The coaching programmes (each with its venue and coach) for the city the player picked.
final coachingListingsProvider =
    FutureProvider.autoDispose<List<CoachingListing>>((ref) {
      final location = ref.watch(selectedCityProvider);
      return ref.watch(venueRepositoryProvider).listCoaching(location);
    });

/// The sport the player had chosen on a Memberships or Coaching card (or in the search card) when they pressed View Plans / View & Enroll.
/// The enrolment page picks it first, then clears it, so a later visit starts fresh.
class PreferredSportController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? sport) => state = sport;
}

final preferredSportProvider =
    NotifierProvider<PreferredSportController, String?>(
      PreferredSportController.new,
    );

// ── Distance: "nearest first" ─────────────────────────────────────────────

/// The device position, asked for once when a venue list opens. Null when the player says no, location is off, or it cannot be read;
/// the lists then keep their usual order. Kept for the session so it is not asked again on every page.
final devicePositionProvider = FutureProvider<(double, double)?>(
  (ref) => ref.watch(deviceLocationProvider).currentPosition(),
);

/// How far each venue of the picked city is from the player, in km (venue id -> km). Empty until both the position and the venues'
/// positions are known, and whenever either is missing, so a page can always sort by it without checking.
final venueDistancesProvider = FutureProvider.autoDispose<Map<String, double>>((
  ref,
) async {
  final here = await ref.watch(devicePositionProvider.future);
  if (here == null) return const {};
  final city = ref.watch(selectedCityProvider);
  final coords = await ref.watch(venueRepositoryProvider).venueCoords(city);
  return {
    for (final e in coords.entries)
      e.key: distanceKm(here.$1, here.$2, e.value.$1, e.value.$2),
  };
});

/// [items] nearest first by [venueId]; the ones with no known distance keep their order after the rest. With no distances at all the
/// list is returned as it is.
List<T> sortNearestFirst<T>(
  List<T> items,
  String Function(T) venueId,
  Map<String, double> km,
) {
  if (km.isEmpty) return items;
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final da = km[venueId(a.$2)];
    final db = km[venueId(b.$2)];
    if (da != null && db != null) {
      final c = da.compareTo(db);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    }
    if (da != null) return -1;
    if (db != null) return 1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// "850 m" under a kilometre, "2.4 km" up to 10, "37 km" beyond.
String distanceLabel(double km) {
  if (km < 1) return '${((km * 1000) / 50).round() * 50} m';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}
