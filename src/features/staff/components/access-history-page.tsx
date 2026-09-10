"use client";

import { useCallback, useEffect, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getStaffService } from "@/services/staff";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import type { SecurityEvent } from "@/features/staff/types";

const PAGE_SIZE = 25;
const ALL = "ALL";

const EVENT_LABELS: Record<string, string> = {
  STAFF_INVITED: "Staff Invited",
  STAFF_LINKED: "Staff Linked",
  STAFF_ACTIVATED: "Reactivated",
  STAFF_DEACTIVATED: "Deactivated",
  STAFF_ROLE_CHANGED: "Role Updated",
  STAFF_PROFILE_UPDATED: "Profile Updated",
  FACILITY_ACCESS_GRANTED: "Facility Access",
  FACILITY_ACCESS_REMOVED: "Facility Access Removed",
  ROLE_CREATED: "Role Created",
  ROLE_UPDATED: "Role Updated",
  ROLE_DELETED: "Role Removed",
  ROLE_PERMISSIONS_UPDATED: "Permissions Updated",
};

export function AccessHistoryPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [event, setEvent] = useState(ALL);
  const [page, setPage] = useState(0);
  const [events, setEvents] = useState<SecurityEvent[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => setPage(0), [event]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const res = await getStaffService().listSecurityEvents({
      facilityId,
      filters: { event: event === ALL ? null : event },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setEvents(res.events);
    setTotalCount(res.totalCount);
  }, [facilityId, event, page]);

  useEffect(() => {
    let cancelled = false;
    setEvents(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load access history.");
      setEvents([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  if (!perms?.can("USERS_VIEW")) return <PermissionDenied message="You don't have permission to view access history." />;

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold">Access History</h1>
        <p className="text-sm text-muted-foreground">Track role changes, access updates and important staff activities.</p>
      </div>

      <Card className="p-4">
        <div className="space-y-1.5">
          <span className="block text-xs text-muted-foreground">Activity</span>
          <Select value={event} onValueChange={setEvent}>
            <SelectTrigger className="w-[14rem]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All Activities</SelectItem>
              {Object.entries(EVENT_LABELS).map(([k, v]) => (
                <SelectItem key={k} value={k}>
                  {v}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <div className="p-10 text-center">
            <p className="text-sm font-semibold text-destructive">Unable to load access history</p>
            <p className="mt-1 text-sm text-muted-foreground">{error}</p>
            <Button type="button" variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : events === null ? (
          <div className="space-y-2 p-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="h-10 w-full rounded-lg" />
            ))}
          </div>
        ) : events.length === 0 ? (
          <p className="p-10 text-center text-sm text-muted-foreground">No activity recorded yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date &amp; Time</TableHead>
                  <TableHead>Staff</TableHead>
                  <TableHead>Action</TableHead>
                  <TableHead>Details</TableHead>
                  <TableHead>Performed By</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {events.map((e) => (
                  <TableRow key={e.id}>
                    <TableCell className="whitespace-nowrap text-muted-foreground">
                      {new Date(e.createdAt).toLocaleString("en-IN", {
                        day: "2-digit",
                        month: "short",
                        year: "numeric",
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </TableCell>
                    <TableCell>{e.targetName ?? "—"}</TableCell>
                    <TableCell>{EVENT_LABELS[e.event] ?? e.event}</TableCell>
                    <TableCell className="max-w-[20rem] truncate text-muted-foreground">{e.summary}</TableCell>
                    <TableCell className="text-muted-foreground">{e.actorName ?? "System"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}

        {totalCount > 0 && (
          <div className="flex items-center justify-between gap-3 border-t border-border p-3">
            <p className="text-xs text-muted-foreground">
              Showing {page * PAGE_SIZE + 1} to {Math.min((page + 1) * PAGE_SIZE, totalCount)} of {totalCount} activities
            </p>
            <div className="flex items-center gap-1">
              <Button type="button" variant="outline" size="sm" aria-label="Previous page" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
                <ChevronLeft className="h-4 w-4" aria-hidden />
              </Button>
              <span className="px-2 text-xs text-muted-foreground">
                {page + 1} / {totalPages}
              </span>
              <Button type="button" variant="outline" size="sm" aria-label="Next page" disabled={page + 1 >= totalPages} onClick={() => setPage((p) => p + 1)}>
                <ChevronRight className="h-4 w-4" aria-hidden />
              </Button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
