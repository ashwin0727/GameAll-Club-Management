import { redirect } from "next/navigation";
import { checkPlatformAdmin, getAuthenticatedUser, getCurrentProfile } from "@/features/auth/api/auth.api";
import { AdminShell } from "@/features/admin/components/admin-shell";

/** Only GameAll's platform admin gets past here; everyone else goes back to their own dashboard (or the login page). */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) redirect("/login");
  if (!(await checkPlatformAdmin(supabase))) redirect("/dashboard");

  // First sign-in: choose your own password before anything else.
  const profile = await getCurrentProfile();
  if (profile?.must_reset_password) redirect("/reset-password?forced=1");

  return <AdminShell email={user.email ?? ""}>{children}</AdminShell>;
}
