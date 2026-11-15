import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile, hasDashboardAccess } from "@/features/auth/api/auth.api";
import { MembershipSessionsPage } from "@/features/membership-sessions/components/membership-sessions-page";

export const metadata: Metadata = {
  title: `Membership Sessions`,
};

export default async function MembershipSessionsRoute() {
  const profile = await getCurrentProfile();

  if (!profile || !(await hasDashboardAccess(profile))) {
    redirect("/dashboard");
  }

  return <MembershipSessionsPage />;
}