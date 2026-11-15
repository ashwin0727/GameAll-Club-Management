import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile, hasDashboardAccess } from "@/features/auth/api/auth.api";
import { PlanDetailsPage } from "@/features/memberships/components/plan-details-page";

export const metadata: Metadata = {
  title: `Membership Plan`,
};

// One plan, read-only — where "View Plan" on the plan-created screen lands.
export default async function Page({ params }: { params: Promise<{ planId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || !(await hasDashboardAccess(profile))) {
    redirect("/dashboard");
  }
  const { planId } = await params;
  return <PlanDetailsPage planId={planId} />;
}
