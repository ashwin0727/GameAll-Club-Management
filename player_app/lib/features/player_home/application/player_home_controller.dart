import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/resilient.dart';
import '../data/pending_payment_repository.dart';
import '../data/player_home_repository.dart';
import '../domain/player_home_models.dart';

/// The data source. Tests override this with a fake.
final playerHomeRepositoryProvider = Provider<PlayerHomeRepository>(
  (ref) => SupabasePlayerHomeRepository(),
);

/// Opens the payment page for an unpaid membership, coaching enrolment or booking. Tests override this with a fake.
final pendingPaymentRepositoryProvider = Provider<PendingPaymentRepository>(
  (ref) => SupabasePendingPaymentRepository(),
);

/// Loads the Home data once, and again on pull-to-refresh.
class PlayerHomeController extends AsyncNotifier<PlayerHomeData> {
  @override
  Future<PlayerHomeData> build() =>
      ref.watch(playerHomeRepositoryProvider).load();

  /// Reloads without blanking the page: the old data stays on screen until the new data arrives.
  ///
  /// Several places ask for this at once (coming back to the app, a payment finishing, a page closing): they all share the one reload
  /// that is already running instead of each sending its own.
  Future<void> refresh() => _inFlight.run('home', _reload);

  final _inFlight = InFlight();

  Future<void> _reload() async {
    final next = await AsyncValue.guard(
      () => ref.read(playerHomeRepositoryProvider).load(),
    );
    // A failed refresh keeps what is already on screen.
    if (next.hasValue || !state.hasValue) state = next;
  }
}

final playerHomeProvider =
    AsyncNotifierProvider<PlayerHomeController, PlayerHomeData>(
      PlayerHomeController.new,
    );

// ── Location ──────────────────────────────────────────────────────────────

/// Cities offered in the location picker (manual selection, so it works without device location permission).
const playerCities = <String>[
  'Bangalore, Karnataka',
  'Chennai, Tamil Nadu',
  'Hyderabad, Telangana',
  'Mumbai, Maharashtra',
  'Delhi NCR, Delhi',
  'Pune, Maharashtra',
  'Kolkata, West Bengal',
  'Kochi, Kerala',
  'Coimbatore, Tamil Nadu',
  'Ahmedabad, Gujarat',
];

class SelectedCity extends Notifier<String> {
  @override
  String build() => playerCities.first;

  void select(String city) => state = city;
}

final selectedCityProvider = NotifierProvider<SelectedCity, String>(
  SelectedCity.new,
);

// ── Theme ─────────────────────────────────────────────────────────────────

/// The theme the app starts with (read from the device before the app runs; dark when nothing was saved). Tests can override it.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.dark);

class ThemeModeController extends Notifier<ThemeMode> {
  static const prefsKey = 'theme_mode';

  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  void set(ThemeMode mode) {
    state = mode;
    _save(mode);
  }

  void toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  Future<void> _save(ThemeMode mode) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(prefsKey, mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
