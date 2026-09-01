import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { GuestBookingEditPage } from "@/features/bookings/components/guest-booking-edit-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Edit Guest Booking — ${APP_NAME}`,
};

export default async function Page({ params }: { params: Promise<{ bookingId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  const { bookingId } = await params;
  return <GuestBookingEditPage bookingId={bookingId} />;
}
