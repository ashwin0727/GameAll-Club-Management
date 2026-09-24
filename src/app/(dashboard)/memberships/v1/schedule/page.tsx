import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { MemberSchedulePage } from "@/features/memberships/components/member-schedule-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Membership Schedule — ${APP_NAME}`,
};

// Sits under the Memberships section: /memberships/v1 is the dashboard, this is its schedule page.
export default async function Page() {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  return <MemberSchedulePage />;
}
