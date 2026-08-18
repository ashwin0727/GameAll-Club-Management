/**
 * Narrows a caller-supplied redirect target to an in-app path.
 *
 * Email links and query strings are attacker-influenced, so anything that could
 * leave the origin — absolute URLs, protocol-relative `//host` — is discarded in
 * favour of the fallback.
 */
export function safeRedirectPath(raw: string | null | undefined, fallback = "/login"): string {
  if (!raw) return fallback;
  if (!raw.startsWith("/")) return fallback;
  if (raw.startsWith("//") || raw.startsWith("/\\")) return fallback;
  return raw;
}