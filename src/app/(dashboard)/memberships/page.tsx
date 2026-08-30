import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { MembershipsPage } from "@/features/memberships/components/memberships-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Memberships — ${APP_NAME}`,
};

export default async function Page() {
  const profile = await getCurrentProfile();

  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }

  return <MembershipsPage />;
}