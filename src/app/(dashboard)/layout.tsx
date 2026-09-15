import { redirect } from "next/navigation";
import { getCurrentProfile, getFacilityContext } from "@/features/auth/api/auth.api";
import { AppShell } from "@/components/shared/app-shell";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  // Both share the same cached auth.getUser() call under the hood, so
  // running them together costs one round trip instead of two sequential ones.
  const [profile, facilityContext] = await Promise.all([getCurrentProfile(), getFacilityContext()]);

  if (!profile) {
    redirect("/login");
  }

  // A staff account created by an administrator signs in with a one-time
  // password and must set their own before doing anything else.
  if (profile.must_reset_password) {
    redirect("/reset-password?forced=1");
  }

  return (
    <AppShell profile={profile} facilityContext={facilityContext}>
      {children}
    </AppShell>
  );
}
