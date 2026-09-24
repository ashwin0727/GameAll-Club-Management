import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { MembershipDashboardPage } from "@/features/memberships/components/membership-dashboard-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Membership Dashboard — ${APP_NAME}`,
};

// The sidebar's "Memberships" item lands here by default. The searchable/filterable member
// list stays at /memberships, reachable via "View All" on this page.
export default async function Page() {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  return <MembershipDashboardPage />;
}
