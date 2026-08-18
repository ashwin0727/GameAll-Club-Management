import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "@/types/database.types";

/** Reachable while signed out: the whole onboarding flow plus the email callback. */
const PUBLIC_ROUTES = [
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
const SESSION_TOLERANT_ROUTES = ["/reset-password", "/"];

function isPublic(pathname: string): boolean {
  return PUBLIC_ROUTES.some(
    (route) => pathname === route || (route !== "/" && pathname.startsWith(`${route}/`)),
  );
}

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Also refreshes an expiring session, which is why this runs on every request.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;
  // /reset-password is public in the sense that an unauthenticated visitor may
  // land there — the page itself explains an invalid link.
  const publicRoute = isPublic(pathname) || pathname.startsWith("/reset-password");

  if (!user && !publicRoute) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    url.searchParams.set("redirectTo", pathname);
    return NextResponse.redirect(url);
  }

  if (user && publicRoute && !SESSION_TOLERANT_ROUTES.includes(pathname)) {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    url.search = "";
    return NextResponse.redirect(url);
  }

  return response;
}