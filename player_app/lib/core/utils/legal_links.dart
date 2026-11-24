import '../config/app_config.dart';

/// GameAll's own public legal pages (Privacy Policy, Terms & Conditions, Cancellation & Refund Policy, account deletion), hosted on
/// play.gameall.co (player_app/web). GameAll Venue has its own set on club.gameall.co. Google Play requires them to be reachable
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
  final base = AppConfig.playSiteUrl.trim().replaceAll(RegExp(r'/+$'), '');
  return Uri.parse('$base${page.path}');
}
