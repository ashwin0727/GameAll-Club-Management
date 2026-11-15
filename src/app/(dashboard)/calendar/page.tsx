import type { Metadata } from "next";
import { BookingOperationsView } from "@/features/bookings/components/booking-operations-view";
import { PageHero } from "@/components/shared/page-hero";

export const metadata: Metadata = {
  title: `Calendar`,
};

export default function BookingsPage() {
  return (
    <div className="space-y-2">
      <PageHero
        title="Calendar"
        subtitle="View all bookings, coaching sessions and important club activities in one place."
        tagline="Plan. Play. Grow Together."
        taglineSub="Stay organized. Never miss a game."
      />
      <BookingOperationsView />
    </div>
  );
}
