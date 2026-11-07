import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/guest_bookings_repository.dart';
import '../domain/guest_booking.dart';

/// The data source. Tests override this with a fake.
final guestBookingsRepositoryProvider = Provider<GuestBookingsRepository>(
  (ref) => SupabaseGuestBookingsRepository(),
);

/// The signed-in player's guest bookings in the page's three tabs. Reloads when invalidated (after paying, on coming back to the page).
final myGuestBookingsProvider = FutureProvider.autoDispose<GuestBookings>(
  (ref) => ref.watch(guestBookingsRepositoryProvider).mine(),
);
