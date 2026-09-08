import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { GuestBookingReport } from "@/features/reports/components/guest-booking-report";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Guest Booking Report — ${APP_NAME}` };

export default function ReportsGuestBookingsPage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/reports" className="hover:text-foreground">
          Reports
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Guest Bookings</span>
      </nav>
      <GuestBookingReport />
    </div>
  );
}
