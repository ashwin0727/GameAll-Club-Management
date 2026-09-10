/// Tournament Management is a SEPARATE application. This app only bridges to
/// it — the destination URLs live here and come from `--dart-define`s (or the
/// `env.json` passed via `--dart-define-from-file`). Nothing is invented: an
/// unset value stays null and its call to action is hidden.
class TournamentAppConfig {
  const TournamentAppConfig({
    this.webUrl,
    this.deepLink,
    this.androidStoreUrl,
    this.iosStoreUrl,
    this.previewAssets = const [
      TournamentPreview('assets/images/tournament-app-home.jpeg', 'Organizer home'),
      TournamentPreview('assets/images/tournament-app-hub.jpeg', 'Tournament hub'),
    ],
  });

  final String? webUrl;
  final String? deepLink;
  final String? androidStoreUrl;
  final String? iosStoreUrl;
  final List<TournamentPreview> previewAssets;

  static String? _clean(String v) => v.trim().isEmpty ? null : v.trim();

  /// Reads the compile-time environment. `const` so it is tree-shaken cleanly.
  static const _webUrl = String.fromEnvironment('TOURNAMENT_WEB_URL');
  static const _deepLink = String.fromEnvironment('TOURNAMENT_DEEP_LINK');
  static const _androidUrl = String.fromEnvironment('TOURNAMENT_ANDROID_URL');
  static const _iosUrl = String.fromEnvironment('TOURNAMENT_IOS_URL');

  factory TournamentAppConfig.fromEnvironment() => TournamentAppConfig(
        webUrl: _clean(_webUrl),
        deepLink: _clean(_deepLink),
        androidStoreUrl: _clean(_androidUrl),
        iosStoreUrl: _clean(_iosUrl),
      );

  bool get hasStores => androidStoreUrl != null || iosStoreUrl != null;

  /// Where "Open Tournament App" points: deep link first on device, then web,
  /// then a store. Null when nothing is configured.
  String? get openUrl => deepLink ?? webUrl ?? androidStoreUrl ?? iosStoreUrl;

  String? get downloadUrl => androidStoreUrl ?? iosStoreUrl;

  String? get availabilityLabel {
    final a = androidStoreUrl != null;
    final i = iosStoreUrl != null;
    if (a && i) return 'Available on Android and iOS';
    if (a) return 'Available on Android';
    if (i) return 'Available on iOS';
    return null;
  }
}

class TournamentPreview {
  const TournamentPreview(this.asset, this.label);
  final String asset;
  final String label;
}
