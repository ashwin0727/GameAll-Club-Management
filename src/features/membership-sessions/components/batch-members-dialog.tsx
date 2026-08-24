"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { getMembershipService } from "@/services/memberships";
import type { MembershipBatch, MembershipBatchMember } from "@/features/membership-sessions/types";
import type { Member } from "@/features/members/types";
import { ServiceError } from "@/services/shared/service-error";

export function BatchMembersDialog({
  open,
  onOpenChange,
  facilityId,
  batch,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  batch: MembershipBatch;
}) {
  const [assigned, setAssigned] = useState<MembershipBatchMember[] | null>(null);
  const [memberNames, setMemberNames] = useState<Record<string, string>>({});
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Pick<Member, "id" | "fullName" | "phone" | "email">[]>([]);
  const [error, setError] = useState<string | null>(null);

  function reload() {
    getMembershipSessionService()
      .getBatchMembers(batch.id)
      .then(async (members) => {
        setAssigned(members);
        const missing = members.filter((m) => !(m.memberId in memberNames));
        if (missing.length > 0) {
          const found = await getMembershipService().searchFacilityMembers(facilityId, { limit: 200 });
          const names: Record<string, string> = {};
          for (const row of found) names[row.memberId] = row.fullName;
          setMemberNames((prev) => ({ ...prev, ...names }));
        }
      })
      .catch(() => setAssigned([]));
  }

  useEffect(() => {
    if (!open) return;
    setQuery("");
    setResults([]);
    setError(null);
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, batch.id]);

  useEffect(() => {
    let cancelled = false;
    if (query.trim().length < 2) {
      setResults([]);
      return;
    }
    const timeout = setTimeout(() => {
      getMembershipService()
        .searchMembers(facilityId, query)
        .then((r) => !cancelled && setResults(r))
        .catch(() => {});
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timeout);
    };
  }, [query, facilityId]);

  async function assign(memberId: string, fullName: string) {
    setError(null);
    try {
      await getMembershipSessionService().assignBatchMember(batch.id, memberId);
      setMemberNames((prev) => ({ ...prev, [memberId]: fullName }));
      setQuery("");
      setResults([]);
      reload();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to assign this member.");
    }
  }

  async function remove(memberId: string) {
    await getMembershipSessionService().removeBatchMember(batch.id, memberId);
    reload();
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{batch.name} — Members</DialogTitle>
          <DialogDescription>Capacity {batch.capacity} · members eligible to book this batch&apos;s sessions.</DialogDescription>
        </DialogHeader>

        {assigned === null ? (
          <Skeleton className="h-32 w-full rounded-lg" />
        ) : (
          <div className="space-y-4">
            {assigned.length === 0 ? (
              <p className="text-sm text-muted-foreground">No members assigned.</p>
            ) : (
              <div className="divide-y rounded-md border border-border">
                {assigned.map((m) => (
                  <div key={m.id} className="flex items-center justify-between p-2 text-sm">
                    <span>{memberNames[m.memberId] ?? m.memberId}</span>
                    <Button type="button" variant="ghost" size="sm" onClick={() => remove(m.memberId)}>
                      Remove
                    </Button>
                  </div>
                ))}
              </div>
            )}

            <div className="space-y-2">
              <input
                aria-label="Search members to assign"
                placeholder="Search by name or phone"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
              />
              {results.length > 0 && (
                <div className="divide-y rounded-md border border-input">
                  {results.map((r) => (
                    <button
                      key={r.id}
                      type="button"
                      onClick={() => assign(r.id, r.fullName)}
                      className="block w-full px-3 py-2 text-left text-sm hover:bg-accent"
                    >
                      {r.fullName} <span className="text-muted-foreground">· {r.phone}</span>
                    </button>
                  ))}
                </div>
              )}
              {error && <p className="text-sm text-destructive">{error}</p>}
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}