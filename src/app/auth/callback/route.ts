import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { safeRedirectPath } from "@/lib/redirects";

/**
 * Landing point for every link Supabase emails: signup confirmation and
 * password recovery.
 *
 * The link carries a one-time code that is exchanged here for a session cookie.
 * `next` decides where the user goes afterwards, and is restricted to in-app
 * paths so the callback can't be used as an open redirect.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const code = searchParams.get("code");
  const next = safeRedirectPath(searchParams.get("next"));

  // Supabase reports link problems (expired, already used) as query params
  // rather than a failed exchange.
  const errorCode = searchParams.get("error_code") ?? searchParams.get("error");
  if (errorCode) {
    const target = next.startsWith("/reset-password") ? "/forgot-password" : "/login";
    return NextResponse.redirect(`${origin}${target}?error=link_expired`);
  }

  if (!code) {
    return NextResponse.redirect(`${origin}/login?error=invalid_link`);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    const target = next.startsWith("/reset-password") ? "/forgot-password" : "/login";
    return NextResponse.redirect(`${origin}${target}?error=link_expired`);
  }

  return NextResponse.redirect(`${origin}${next}`);
}