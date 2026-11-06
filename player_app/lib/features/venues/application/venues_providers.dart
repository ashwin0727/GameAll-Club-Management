import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player_home/application/player_home_controller.dart';
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
