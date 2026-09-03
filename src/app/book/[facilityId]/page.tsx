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
 */
export default async function PublicBookingPage({ params }: { params: Promise<{ facilityId: string }> }) {
  const { facilityId } = await params;

  return (
    <main className="min-h-screen bg-background">
      <PublicBookingFlow facilityId={facilityId} />
    </main>
  );
}
