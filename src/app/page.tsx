import { getCurrentAuthUser } from "@/features/auth/api/auth.api";
import { SplashScreen } from "@/features/auth/components/splash-screen";

/**
 * Application entry. The session is resolved here, on the server, so the splash
 * never renders a route the user cannot reach. The remaining decision — Welcome
 * for a first visit, Login for a returning one — depends on device state and is
 * made in the client component.
 */
export default async function RootPage() {
  const user = await getCurrentAuthUser();

  return (
    <SplashScreen signedIn={Boolean(user)} onboardingCompleted={user?.onboardingCompleted ?? false} />
  );
}