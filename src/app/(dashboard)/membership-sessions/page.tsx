import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { MembershipSessionsPage } from "@/features/membership-sessions/components/membership-sessions-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Membership Sessions — ${APP_NAME}`,
};

export default async function MembershipSessionsRoute() {
  const profile = await getCurrentProfile();

  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }

  return <MembershipSessionsPage />;
}