import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { GuestBookingsDashboard } from "@/features/bookings/components/guest-bookings-dashboard";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Guest Bookings — ${APP_NAME}`,
};

export default async function Page() {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  return <GuestBookingsDashboard />;
}