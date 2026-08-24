import type { Metadata } from "next";
import { BookingOperationsView } from "@/features/bookings/components/booking-operations-view";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Bookings — ${APP_NAME}`,
};

export default function BookingsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Bookings</h1>
        <p className="text-sm text-muted-foreground">See what&apos;s free, what&apos;s booked, and book a court in seconds.</p>
      </div>
      <BookingOperationsView />
    </div>
  );
}