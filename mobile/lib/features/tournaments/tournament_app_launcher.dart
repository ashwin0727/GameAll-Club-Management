import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

enum TournamentLaunchResult { opened, notConfigured, failed }

typedef UrlLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

/// Attempts to open the separate Tournament Management app: the deep link (or
/// configured URL) in an external application, reporting a typed result so the
/// screen can show a graceful "couldn't open" state instead of a raw error.
class TournamentAppLauncher {
  TournamentAppLauncher({UrlLauncher? launcher}) : _launch = launcher ?? launchUrl;

  final UrlLauncher _launch;

  Future<TournamentLaunchResult> open(String? url) async {
    if (url == null || url.trim().isEmpty) return TournamentLaunchResult.notConfigured;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return TournamentLaunchResult.failed;
    try {
      final ok = await _launch(uri, mode: LaunchMode.externalApplication);
      return ok ? TournamentLaunchResult.opened : TournamentLaunchResult.failed;
    } catch (e) {
      debugPrint('[tournament] launch failed: $e');
      return TournamentLaunchResult.failed;
    }
  }
}
