import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { CreatePlanWizardPage } from "@/features/memberships/components/create-plan-wizard-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Create Membership Plan — ${APP_NAME}`,
};

// Sits under Membership Plans: /memberships/v1/plans lists them, this creates a new one.
export default async function Page() {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  return <CreatePlanWizardPage />;
}
