import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { PlanDetailsPage } from "@/features/memberships/components/plan-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Membership Plan — ${APP_NAME}`,
};

// One plan, read-only — where "View Plan" on the plan-created screen lands.
export default async function Page({ params }: { params: Promise<{ planId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  const { planId } = await params;
  return <PlanDetailsPage planId={planId} />;
}
