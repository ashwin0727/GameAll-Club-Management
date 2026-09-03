import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "@/types/database.types";
import {
  SESSION_TOLERANT_ROUTES,
  isPublic,
  isStandalonePublic,
} from "@/lib/supabase/public-routes";

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

  // getSession() reads the cookie locally (refreshing only if the token is
  // actually near expiry) instead of round-tripping to the Auth server on
  // every navigation like getUser() does. That's safe here because this
  // check only decides routing/redirects — the real authorization check is
  // the server-verified getUser() call every protected layout already makes
  // (see getCurrentAuthUser/getCurrentProfile), which still blocks a stale
  // or forged cookie before any data renders.
  const {
    data: { session },
  } = await supabase.auth.getSession();
  const user = session?.user ?? null;

  const { pathname } = request.nextUrl;
  // /reset-password is public in the sense that an unauthenticated visitor may
  // land there — the page itself explains an invalid link.
  const standalone = isStandalonePublic(pathname);
  const publicRoute = isPublic(pathname) || standalone || pathname.startsWith("/reset-password");

  if (!user && !publicRoute) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    url.searchParams.set("redirectTo", pathname);
    return NextResponse.redirect(url);
  }

  if (user && publicRoute && !standalone && !SESSION_TOLERANT_ROUTES.includes(pathname)) {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    url.search = "";
    return NextResponse.redirect(url);
  }

  return response;
}