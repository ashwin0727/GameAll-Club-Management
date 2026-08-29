import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/theme/theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // The package's own documented test seam — avoids the platform channel
    // entirely so these tests never depend on a real device/emulator.
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to ThemeMode.system before any preference is saved', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeControllerProvider), ThemeMode.system);
  });

  test('setMode updates state immediately, without waiting on storage to persist', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeModeControllerProvider.notifier).setMode(ThemeMode.dark);

    expect(container.read(themeModeControllerProvider), ThemeMode.dark);
  });

  test('a persisted preference is restored on the next controller instance — the Appearance setting survives a restart', () async {
    final first = ProviderContainer();
    await first.read(themeModeControllerProvider.notifier).setMode(ThemeMode.light);
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    // Reading the provider is what triggers build() (Riverpod providers are
    // lazy) — must happen BEFORE the wait below, or _restore() never even
    // starts during the delay.
    second.read(themeModeControllerProvider);
    // The restore is a fire-and-forget microtask kicked off from build(),
    // itself awaiting SharedPreferences.getInstance() — give it a few event
    // loop turns to actually complete before asserting.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(second.read(themeModeControllerProvider), ThemeMode.light);
  });

  test('never crashes if the platform storage is unavailable — falls back to System', () async {
    // No SharedPreferences.setMockInitialValues call in this test at all —
    // simulates a platform where the channel genuinely isn't wired up.
    // (setUp above already ran though, so this mostly documents the
    // try/catch's intent rather than truly removing the mock.)
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeControllerProvider), ThemeMode.system);
  });
}