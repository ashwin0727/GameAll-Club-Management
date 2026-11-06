import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Future<void> refresh() async {
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

// ── Sports ────────────────────────────────────────────────────────────────

class SportOption {
  const SportOption(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  /// The sport name as the database spells it; null for "All" and "More".
  String? get sportName => (id == 'all' || id == 'more') ? null : label;
}

const sportOptions = <SportOption>[
  SportOption('all', 'All', Icons.grid_view_rounded),
  SportOption('badminton', 'Badminton', Icons.sports_tennis_rounded),
  SportOption('football', 'Football', Icons.sports_soccer_rounded),
  SportOption('tennis', 'Tennis', Icons.sports_baseball_rounded),
  SportOption('pickleball', 'Pickleball', Icons.sports_handball_rounded),
  SportOption('more', 'More', Icons.more_horiz_rounded),
];

class SelectedSport extends Notifier<String> {
  @override
  String build() => 'all';

  void select(String id) => state = id;
}

final selectedSportProvider = NotifierProvider<SelectedSport, String>(
  SelectedSport.new,
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

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void set(ThemeMode mode) => state = mode;

  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
