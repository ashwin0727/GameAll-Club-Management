"use client";

import { Sidebar } from "@/components/shared/sidebar";
import { Topbar } from "@/components/shared/topbar";
import { PermissionProvider } from "@/features/auth/context/permission-provider";
import type { FacilityContext } from "@/features/auth/api/auth.api";
import type { Profile } from "@/features/auth/types";

export function AppShell({
  profile,
  facilityContext,
  children,
}: {
  profile: Profile;
  facilityContext: FacilityContext | null;
  children: React.ReactNode;
}) {
  const shell = (
    <div className="flex min-h-screen">
      <Sidebar role={profile.role} />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar profile={profile} />
        <main className="min-w-0 flex-1 overflow-x-hidden bg-muted/20 p-4 lg:p-6">{children}</main>
      </div>
    </div>
  );

  return facilityContext ? (
    <PermissionProvider context={facilityContext}>{shell}</PermissionProvider>
  ) : (
    shell
  );
}
