import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'gameall.appearance.themeMode';

/// The user's Appearance preference (spec §"Settings": System/Light/Dark).
/// A UI/device-level preference, not business data — persisted locally via
/// SharedPreferences the same way a native app remembers this, never
/// treated as authoritative backend state (spec §"No Mock Persistence" is
/// about domain data: bookings, payments, membership, finance — this is
/// neither).
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      state = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // No persisted preference yet, or the platform storage is
      // unavailable — System is a safe, correct default either way.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // Preference simply won't survive a restart — never block the
      // in-session theme change on storage succeeding.
    }
  }
}

final themeModeControllerProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);