import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { EditMemberPage } from "@/features/memberships/components/edit-member-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Edit Member — ${APP_NAME}`,
};

// The Memberships section's own edit-member page: the dashboard's "Edit" actions land here.
export default async function Page({ params }: { params: Promise<{ membershipId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  const { membershipId } = await params;
  return <EditMemberPage membershipId={membershipId} />;
}
