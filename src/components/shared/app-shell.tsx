"use client";

import { Sidebar } from "@/components/shared/sidebar";
import { Topbar } from "@/components/shared/topbar";
import type { Profile } from "@/features/auth/types";

export function AppShell({ profile, children }: { profile: Profile; children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen">
      <Sidebar role={profile.role} />
      <div className="flex flex-1 flex-col">
        <Topbar profile={profile} />
        <main className="flex-1 bg-muted/20 p-4 lg:p-6">{children}</main>
      </div>
    </div>
  );
}