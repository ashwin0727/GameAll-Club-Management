import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/resilient.dart';
import '../../auth/application/auth_providers.dart';
import '../data/profile_repository.dart';
import '../domain/profile_models.dart';

/// The profile's data source. Tests override this with a fake.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(),
);

/// The full profile (Player ID, date of birth, gender, city, photo). Falls back to the basic profile so the screen is never empty.
final profileDetailsProvider = FutureProvider.autoDispose<ProfileDetails?>((
  ref,
) async {
  final basic = ref.watch(currentPlayerProvider);
  if (basic == null) return null;
  try {
    final full = await retryTransient(
      () => ref.read(profileRepositoryProvider).details(),
    );
    return full ?? ProfileDetails.fromBasic(basic);
  } catch (_) {
    return ProfileDetails.fromBasic(basic);
  }
});

/// GameAll's sports a player can mark as preferred (empty when they cannot be read).
final platformSportsProvider = FutureProvider.autoDispose<List<SportOption>>((
  ref,
) async {
  try {
    return await ref.read(profileRepositoryProvider).sports();
  } catch (_) {
    return const [];
  }
});

/// The numbers under the name (null when they cannot be read: the screen then shows dashes).
final profileStatsProvider = FutureProvider.autoDispose<ProfileStats?>((
  ref,
) async {
  if (ref.watch(currentPlayerProvider) == null) return null;
  try {
    return await retryTransient(
      () => ref.read(profileRepositoryProvider).stats(),
    );
  } catch (_) {
    return null;
  }
});

/// Payments and refunds, newest first.
final paymentHistoryProvider = FutureProvider.autoDispose<List<PaymentRecord>>(
  (ref) => retryTransient(() => ref.read(profileRepositoryProvider).payments()),
);

/// Which reminders the player wants. Kept on the device.
class PlayerPrefs {
  const PlayerPrefs({
    this.bookingReminders = true,
    this.paymentReminders = true,
    this.offers = false,
  });

  final bool bookingReminders;
  final bool paymentReminders;
  final bool offers;

  PlayerPrefs copyWith({
    bool? bookingReminders,
    bool? paymentReminders,
    bool? offers,
  }) => PlayerPrefs(
    bookingReminders: bookingReminders ?? this.bookingReminders,
    paymentReminders: paymentReminders ?? this.paymentReminders,
    offers: offers ?? this.offers,
  );
}

class PlayerPrefsController extends Notifier<PlayerPrefs> {
  static const _kBooking = 'pref_booking_reminders';
  static const _kPayment = 'pref_payment_reminders';
  static const _kOffers = 'pref_offers';

  @override
  PlayerPrefs build() {
    _load();
    return const PlayerPrefs();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = PlayerPrefs(
        bookingReminders: p.getBool(_kBooking) ?? true,
        paymentReminders: p.getBool(_kPayment) ?? true,
        offers: p.getBool(_kOffers) ?? false,
      );
    } catch (_) {}
  }

  Future<void> _save(String key, bool v) async {
    try {
      (await SharedPreferences.getInstance()).setBool(key, v);
    } catch (_) {}
  }

  void setBooking(bool v) {
    state = state.copyWith(bookingReminders: v);
    _save(_kBooking, v);
  }

  void setPayment(bool v) {
    state = state.copyWith(paymentReminders: v);
    _save(_kPayment, v);
  }

  void setOffers(bool v) {
    state = state.copyWith(offers: v);
    _save(_kOffers, v);
  }
}

final playerPrefsProvider = NotifierProvider<PlayerPrefsController, PlayerPrefs>(
  PlayerPrefsController.new,
);
