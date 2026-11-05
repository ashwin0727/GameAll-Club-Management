/// Whether [value] looks like a Google Maps location link: what "Share → Copy link" gives on a phone (maps.app.goo.gl/…, goo.gl/maps/…,
/// g.page/…) or what a browser's address bar shows (google.com/maps/…, maps.google.com/…, google.co.in/maps/…). This only checks the
/// shape; GameAll's admin opens the link to confirm it is the right place. Same rules as the website's `isGoogleMapsLink`.
bool isGoogleMapsLink(String value) {
  final Uri url;
  try {
    url = Uri.parse(value.trim());
  } catch (_) {
    return false;
  }
  if (!url.hasScheme || (url.scheme != 'https' && url.scheme != 'http')) return false;
  final host = url.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final path = url.path.toLowerCase();
  if (host == 'maps.app.goo.gl' || host == 'g.page' || host == 'share.google') return path.length > 1;
  if (host == 'goo.gl') return path.startsWith('/maps');
  if (host == 'maps.google.com' || RegExp(r'^maps\.google\.[a-z.]+$').hasMatch(host)) return true;
  if (RegExp(r'^google\.[a-z.]+$').hasMatch(host)) return path.startsWith('/maps');
  return false;
}
