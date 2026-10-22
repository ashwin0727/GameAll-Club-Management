import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { ProfileHubPage } from "@/features/profile/components/profile-hub-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Profile — ${APP_NAME}`,
};

export default async function ProfilePage() {
  const profile = await getCurrentProfile();
  if (!profile) redirect("/login");
  return <ProfileHubPage profile={profile} />;
}
