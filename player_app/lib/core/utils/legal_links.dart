import '../config/app_config.dart';

/// The public legal pages, hosted on the GameAll website and shared by GameAll Play and GameAll Venue (one Privacy Policy, one
/// Terms & Conditions, one Cancellation & Refund Policy, one account-deletion page). Google Play requires them to be reachable
/// from inside the app.
enum LegalPage {
  privacy('/privacy'),
  terms('/terms'),
  refunds('/refund-policy'),
  deleteAccount('/delete-account');

  const LegalPage(this.path);
  final String path;
}

Uri legalUri(LegalPage page) {
  final base = AppConfig.clubSiteUrl.trim().replaceAll(RegExp(r'/+$'), '');
  return Uri.parse('$base${page.path}');
}
