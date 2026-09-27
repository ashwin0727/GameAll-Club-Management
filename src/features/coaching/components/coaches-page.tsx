"use client";

import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { CoachesListPanel } from "@/features/coaching/components/coaches-list-panel";
import { PageHeader } from "@/features/coaching/components/shared";

export function CoachesPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  if (!facilityId) return null;

  return (
    <div className="space-y-4">
      <PageHeader title="Coaches" subtitle="Manage your coaching team, their schedules and availability." />
      {/* The panel renders its own Add Coach button (opening the slide-over), so the page header
          doesn't need a second one. */}
      <CoachesListPanel facilityId={facilityId} showAddButton />
    </div>
  );
}
