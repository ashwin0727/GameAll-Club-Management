import type { Metadata } from "next";
import { PublicBookingFlow } from "@/features/public-booking/components/public-booking-flow";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Book a court — ${APP_NAME}`,
  description: "Pick a court and time, and book in a few taps. Pay at the venue.",
};

/**
 * Public, unauthenticated court booking — deliberately outside the
 * (dashboard) route group, so it renders without the admin shell: no
 * sidebar, no topbar, no management navigation.
 *
 * Two ways a club can use this page:
 *
 *   1. link to it directly — /book/<facilityId>
 *   2. embed it in their own site with /embed.js, which loads this same
 *      page with ?embed=1 inside an iframe
 *
 * In embed mode the page drops its outer padding and branding so it reads
 * as part of the host site, and reports its height to the parent frame.
 */
export default async function PublicBookingPage({
  params,
  searchParams,
}: {
  params: Promise<{ facilityId: string }>;
  searchParams: Promise<{ embed?: string; sport?: string }>;
}) {
  const { facilityId } = await params;
  const { embed, sport } = await searchParams;
  const embedded = embed === "1" || embed === "true";

  return (
    <main className={embedded ? "bg-transparent" : "min-h-screen bg-background"}>
      <PublicBookingFlow facilityId={facilityId} embedded={embedded} initialSportId={sport} />
    </main>
  );
}
