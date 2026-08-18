import { createClient } from "@/lib/supabase/server";
import { SplashScreen } from "@/features/auth/components/splash-screen";

/**
 * Application entry. The session is resolved here, on the server, so the splash
 * never renders a route the user cannot reach. The remaining decision — Welcome
 * for a first visit, Login for a returning one — depends on device state and is
 * made in the client component.
 */
export default async function RootPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return <SplashScreen signedIn={Boolean(user)} />;
}