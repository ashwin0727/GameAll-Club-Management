import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile, hasDashboardAccess } from "@/features/auth/api/auth.api";
import { CreateMembershipPage } from "@/features/memberships/components/create-membership-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Create Membership — ${APP_NAME}`,
};

export default async function Page() {
  const profile = await getCurrentProfile();
  if (!profile || !(await hasDashboardAccess(profile))) {
    redirect("/dashboard");
  }
  return <CreateMembershipPage />;
}