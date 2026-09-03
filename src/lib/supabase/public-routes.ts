/** Reachable while signed out: the whole onboarding flow plus the email callback. */
export const PUBLIC_ROUTES = [
  "/",
  "/welcome",
  "/signup",
  "/verify-email",
  "/login",
  "/forgot-password",
  "/auth/callback",
];

/**
 * Signed-in users are bounced off the signed-out screens — except these.
 * /reset-password *requires* the session the recovery link just created, and
 * / is the splash, which routes signed-in users onward itself.
 */
export const SESSION_TOLERANT_ROUTES = ["/reset-password", "/"];

/**
 * Pages for the public — players booking a court, or joining a membership —
 * rather than for facility staff.
 *
 * These render identically whether or not anyone is signed in, and are never
 * redirected in either direction. Sending a signed-out visitor to /login
 * would defeat the point of a shareable link; bouncing a signed-in one to
 * /dashboard would stop an owner previewing their own booking page, and
 * would break the embedded widget for any visitor who happens to have an
 * account here.
 */
export const STANDALONE_PUBLIC_ROUTES = ["/book", "/join"];

export function isPublic(pathname: string): boolean {
  return PUBLIC_ROUTES.some(
    (route) => pathname === route || (route !== "/" && pathname.startsWith(`${route}/`)),
  );
}

export function isStandalonePublic(pathname: string): boolean {
  return STANDALONE_PUBLIC_ROUTES.some(
    (route) => pathname === route || pathname.startsWith(`${route}/`),
  );
}

export type RouteAction = "allow" | "to-login" | "to-dashboard";

/** The middleware's whole redirect decision, as a pure function. */
export function routeAction(pathname: string, signedIn: boolean): RouteAction {
  const standalone = isStandalonePublic(pathname);
  const publicRoute = isPublic(pathname) || standalone || pathname.startsWith("/reset-password");

  if (!signedIn && !publicRoute) return "to-login";
  if (signedIn && publicRoute && !standalone && !SESSION_TOLERANT_ROUTES.includes(pathname)) {
    return "to-dashboard";
  }
  return "allow";
}
