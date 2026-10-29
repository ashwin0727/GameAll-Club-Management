import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';

/// The public legal pages hosted on the GameAll website (required by Google Play).
enum LegalPage {
  privacy('/privacy'),
  terms('/terms'),
  deleteAccount('/delete-account');

  const LegalPage(this.path);
  final String path;
}

/// Where the website lives. [AppConfig.webAppUrl] (WEB_APP_URL in env.json) when set, otherwise the production address.
String get _siteBase {
  final configured = AppConfig.webAppUrl.trim();
  return (configured.isEmpty ? 'https://club.gameall.co' : configured).replaceAll(RegExp(r'/+$'), '');
}

Uri legalUri(LegalPage page) => Uri.parse('$_siteBase${page.path}');

/// Opens a legal page in the browser. Returns false when nothing could handle the link.
Future<bool> openLegalPage(LegalPage page) async {
  try {
    return await launchUrl(legalUri(page), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
