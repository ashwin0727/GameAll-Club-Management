import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile, hasDashboardAccess } from "@/features/auth/api/auth.api";
import { GuestBookingsDashboard } from "@/features/bookings/components/guest-bookings-dashboard";

export const metadata: Metadata = {
  title: `Guest Bookings`,
};

export default async function Page() {
  const profile = await getCurrentProfile();
  if (!profile || !(await hasDashboardAccess(profile))) {
    redirect("/dashboard");
  }
  return <GuestBookingsDashboard />;
}