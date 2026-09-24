import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { PotentialMembersPage } from "@/features/bookings/components/potential-members-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Potential Members — ${APP_NAME}`,
};

// Deliberately not in the sidebar: it is reached from the Guest Insights pop-up on Guest Bookings.
export default async function Page() {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  return <PotentialMembersPage />;
}
