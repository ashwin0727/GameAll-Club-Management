"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { getMembershipService } from "@/services/memberships";
import { computeMembershipStatus, type MembershipDisplayStatus } from "@/features/memberships/status";
import type { FacilityMemberRow } from "@/features/memberships/types";
import { MemberFormDialog } from "@/features/members/components/member-form-dialog";
import { AssignMembershipDialog } from "@/features/memberships/components/assign-membership-dialog";
import { MembershipPlansDialog } from "@/features/memberships/components/membership-plans-dialog";
import { MemberProfileDialog } from "@/features/memberships/components/member-profile-dialog";

const STATUS_FILTERS: (MembershipDisplayStatus | "ALL")[] = [
  "ALL",
  "ACTIVE",
  "EXPIRING_SOON",
  "EXPIRED",
  "CANCELLED",
  "NO_MEMBERSHIP",
];

function statusTone(status: MembershipDisplayStatus): "success" | "warning" | "destructive" | "secondary" {
  switch (status) {
    case "ACTIVE":
      return "success";
    case "EXPIRING_SOON":
      return "warning";
    case "EXPIRED":
      return "destructive";
    case "CANCELLED":
    case "NO_MEMBERSHIP":
      return "secondary";
  }
}

function statusLabel(status: MembershipDisplayStatus): string {
  if (status === "NO_MEMBERSHIP") return "no membership";
  return status.replace("_", " ").toLowerCase();
}

export function MemberList() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");

  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<MembershipDisplayStatus | "ALL">("ALL");
  const [members, setMembers] = useState<FacilityMemberRow[]>([]);
  const [listLoading, setListLoading] = useState(false);

  const [addOpen, setAddOpen] = useState(false);
  const [plansOpen, setPlansOpen] = useState(false);
  const [assignForMemberId, setAssignForMemberId] = useState<string | null>(null);
  const [selectedMember, setSelectedMember] = useState<FacilityMemberRow | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const facility = await getFacilityService().getFacility();
      if (cancelled) return;
      if (!facility) {
        setLoadState("none");
        return;
      }
      setFacilityId(facility.id);
      setLoadState("ready");
    })().catch(() => setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  function reload() {
    if (!facilityId) return;
    setListLoading(true);
    getMembershipService()
      .searchFacilityMembers(facilityId, { query })
      .then((result) => {
        setMembers(result);
        setListLoading(false);
      })
      .catch(() => setListLoading(false));
  }

  useEffect(() => {
    if (!facilityId) return;
    const timeout = setTimeout(reload, 250);
    return () => clearTimeout(timeout);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [facilityId, query]);

  function rowStatus(m: FacilityMemberRow): MembershipDisplayStatus {
    return computeMembershipStatus(m.status !== null && m.endDate !== null ? { status: m.status, endDate: m.endDate } : null);
  }

  const filtered = members.filter((m) => statusFilter === "ALL" || rowStatus(m) === statusFilter);

  if (loadState === "loading") {
    return (
      <div className="space-y-3">
        <Skeleton className="h-11 w-full rounded-md" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }
  if (loadState === "none") {
    return <p className="text-sm text-muted-foreground">Complete your facility setup before managing members.</p>;
  }
  if (loadState === "error" || !facilityId) {
    return <p className="text-sm text-muted-foreground">Unable to load members. Please try again.</p>;
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-1 flex-wrap gap-2">
          <input
            aria-label="Search members"
            placeholder="Search by name, phone, or email"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="h-11 w-full max-w-sm rounded-md border border-input bg-secondary/60 px-3 text-sm"
          />
          <select
            aria-label="Status filter"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value as MembershipDisplayStatus | "ALL")}
            className="h-11 rounded-md border border-input bg-secondary/60 px-3 text-sm capitalize"
          >
            {STATUS_FILTERS.map((s) => (
              <option key={s} value={s} className="capitalize">
                {s === "ALL" ? "All statuses" : statusLabel(s)}
              </option>
            ))}
          </select>
        </div>
        <div className="flex gap-2">
          <Button type="button" variant="outline" onClick={() => setPlansOpen(true)}>
            Membership Plans
          </Button>
          <Button type="button" onClick={() => setAddOpen(true)}>
            + Add Member
          </Button>
        </div>
      </div>

      {listLoading ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : filtered.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
          {members.length === 0 ? "No members yet — add your first member to start tracking memberships." : "No members match your filters."}
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border">
          <table className="w-full text-sm">
            <thead className="bg-secondary/50 text-left text-xs text-muted-foreground">
              <tr>
                <th className="p-3">Member</th>
                <th className="p-3">Plan</th>
                <th className="p-3">Expires</th>
                <th className="p-3">Status</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((m) => {
                const status = rowStatus(m);
                return (
                  <tr
                    key={m.memberId}
                    className="cursor-pointer border-t border-border hover:bg-accent"
                    onClick={() => setSelectedMember(m)}
                  >
                    <td className="p-3">
                      <p className="font-medium">{m.fullName}</p>
                      <p className="text-xs text-muted-foreground">{m.phone}</p>
                    </td>
                    <td className="p-3 text-muted-foreground">{m.planName ?? "—"}</td>
                    <td className="p-3 text-muted-foreground">
                      {m.endDate
                        ? new Date(m.endDate).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })
                        : "—"}
                    </td>
                    <td className="p-3">
                      <Badge variant={statusTone(status)} className="capitalize">
                        {statusLabel(status)}
                      </Badge>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <MemberFormDialog
        open={addOpen}
        onOpenChange={setAddOpen}
        facilityId={facilityId}
        onCreated={(memberId) => {
          setAssignForMemberId(memberId);
          reload();
        }}
        onViewExisting={(memberId) => setAssignForMemberId(memberId)}
      />

      <MembershipPlansDialog open={plansOpen} onOpenChange={setPlansOpen} facilityId={facilityId} />

      {assignForMemberId && (
        <AssignMembershipDialog
          open={assignForMemberId !== null}
          onOpenChange={(open) => !open && setAssignForMemberId(null)}
          facilityId={facilityId}
          memberId={assignForMemberId}
          memberName={members.find((m) => m.memberId === assignForMemberId)?.fullName ?? "New member"}
          onAssigned={() => {
            setAssignForMemberId(null);
            reload();
          }}
        />
      )}

      <MemberProfileDialog
        open={selectedMember !== null}
        onOpenChange={(open) => !open && setSelectedMember(null)}
        facilityId={facilityId}
        member={selectedMember}
        onChanged={() => {
          reload();
        }}
      />
    </div>
  );
}