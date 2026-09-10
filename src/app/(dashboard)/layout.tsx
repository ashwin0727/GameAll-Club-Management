import { redirect } from "next/navigation";
import { getCurrentProfile, getFacilityContext } from "@/features/auth/api/auth.api";
import { AppShell } from "@/components/shared/app-shell";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const profile = await getCurrentProfile();

  if (!profile) {
    redirect("/login");
  }

  // A staff account created by an administrator signs in with a one-time
  // password and must set their own before doing anything else.
  if (profile.must_reset_password) {
    redirect("/reset-password?forced=1");
  }

  const facilityContext = await getFacilityContext();

  return (
    <AppShell profile={profile} facilityContext={facilityContext}>
      {children}
    </AppShell>
  );
}
