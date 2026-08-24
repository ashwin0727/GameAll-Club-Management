import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { MemberList } from "@/features/members/components/member-list";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Members — ${APP_NAME}`,
};

export default async function MembersPage() {
  const profile = await getCurrentProfile();

  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Members</h1>
        <p className="text-sm text-muted-foreground">Manage facility members and their memberships.</p>
      </div>
      <MemberList />
    </div>
  );
}