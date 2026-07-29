import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { MembersTable } from "@/features/members/components/members-table";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Members — ${APP_NAME}`,
};

export default async function MembersPage() {
  const supabase = await createClient();
  const profile = await getCurrentProfile(supabase);

  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Members</h1>
        <p className="text-sm text-muted-foreground">Manage club members and their accounts.</p>
      </div>
      <MembersTable />
    </div>
  );
}