import type { Metadata } from "next";
import { PublicBookingLanding } from "@/features/public-booking/components/public-booking-landing";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Book a court — ${APP_NAME}`,
  description: "Book your favourite court in a few steps. Pay at the venue.",
};

/**
 * Step 0 of the public journey — the venue's front door, before any booking
 * decisions. Outside the (dashboard) route group, so no admin shell renders.
 *
 * "Start Booking" continues to /book/<facilityId>/booking, carrying the
 * facility so the player never chooses it twice.
 */
export default async function PublicBookingLandingPage({
  params,
}: {
  params: Promise<{ facilityId: string }>;
}) {
  const { facilityId } = await params;

  return (
    <main className="min-h-screen bg-background">
      <PublicBookingLanding facilityId={facilityId} />
    </main>
  );
}
