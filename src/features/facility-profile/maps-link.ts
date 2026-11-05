/**
 * Whether [value] looks like a Google Maps location link: what "Share → Copy link" gives on a phone (maps.app.goo.gl/…, goo.gl/maps/…,
 * g.page/…) or what the browser address bar shows (google.com/maps/…, maps.google.com/…, google.co.in/maps/…). This only checks the
 * shape; the admin opens the link to confirm it is the right place.
 */
export function isGoogleMapsLink(value: string): boolean {
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    return false;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return false;
  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  const path = url.pathname.toLowerCase();
  if (host === "maps.app.goo.gl" || host === "g.page" || host === "share.google") return path.length > 1;
  if (host === "goo.gl") return path.startsWith("/maps");
  if (host === "maps.google.com" || /^maps\.google\.[a-z.]+$/.test(host)) return true;
  if (/^google\.[a-z.]+$/.test(host)) return path.startsWith("/maps");
  return false;
}
