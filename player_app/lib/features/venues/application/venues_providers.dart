import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player_home/application/player_home_controller.dart';
import '../data/venue_repository.dart';
import '../domain/venue.dart';

/// The data source. Tests override this with a fake.
final venueRepositoryProvider = Provider<VenueRepository>(
  (ref) => SupabaseVenueRepository(),
);

/// The venues for the city the player picked. Picking another city loads that city's venues by itself.
final venuesForSelectedCityProvider = FutureProvider.autoDispose<List<Venue>>((
  ref,
) {
  final location = ref.watch(selectedCityProvider);
  return ref.watch(venueRepositoryProvider).listForLocation(location);
});
