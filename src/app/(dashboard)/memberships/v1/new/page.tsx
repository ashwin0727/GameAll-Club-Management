import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { AddMemberWizardPage } from "@/features/memberships/components/add-member-wizard-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Add New Member — ${APP_NAME}`,
};

// The Memberships section's own add-member flow: /memberships/v1 is the dashboard, this is
// where its "Add New Member" button lands.
export default async function Page() {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  return <AddMemberWizardPage />;
}
