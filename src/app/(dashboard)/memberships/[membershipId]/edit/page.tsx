import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { CreateMembershipPage } from "@/features/memberships/components/create-membership-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Edit Membership — ${APP_NAME}`,
};

export default async function Page({ params }: { params: Promise<{ membershipId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  const { membershipId } = await params;
  return <CreateMembershipPage membershipId={membershipId} />;
}