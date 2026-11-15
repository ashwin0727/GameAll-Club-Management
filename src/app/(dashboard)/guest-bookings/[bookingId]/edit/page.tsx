import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile, hasDashboardAccess } from "@/features/auth/api/auth.api";
import { GuestBookingEditPage } from "@/features/bookings/components/guest-booking-edit-page";

export const metadata: Metadata = {
  title: `Edit Guest Booking`,
};

export default async function Page({ params }: { params: Promise<{ bookingId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || !(await hasDashboardAccess(profile))) {
    redirect("/dashboard");
  }
  const { bookingId } = await params;
  return <GuestBookingEditPage bookingId={bookingId} />;
}
