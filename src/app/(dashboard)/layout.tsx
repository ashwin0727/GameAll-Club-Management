import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { AppShell } from "@/components/shared/app-shell";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const profile = await getCurrentProfile(supabase);

  if (!profile) {
    redirect("/login");
  }

  return <AppShell profile={profile}>{children}</AppShell>;
}