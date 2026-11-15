import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile, hasDashboardAccess } from "@/features/auth/api/auth.api";
import { CreateMembershipPage } from "@/features/memberships/components/create-membership-page";

export const metadata: Metadata = {
  title: `Edit Membership`,
};

export default async function Page({ params }: { params: Promise<{ membershipId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || !(await hasDashboardAccess(profile))) {
    redirect("/dashboard");
  }
  const { membershipId } = await params;
  return <CreateMembershipPage membershipId={membershipId} />;
}