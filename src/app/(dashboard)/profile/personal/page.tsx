import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { PersonalInfoPage } from "@/features/profile/components/personal-info-page";

export const metadata: Metadata = {
  title: `Personal Information`,
};

export default async function PersonalPage() {
  const profile = await getCurrentProfile();
  if (!profile) redirect("/login");
  return <PersonalInfoPage profile={profile} />;
}
