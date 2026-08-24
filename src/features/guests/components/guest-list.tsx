"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { getGuestService } from "@/services/guests";
import type { GuestPlayer } from "@/features/guests/types";
import { GuestFormDialog } from "@/features/guests/components/guest-form-dialog";
import { GuestProfileDialog } from "@/features/guests/components/guest-profile-dialog";

export function GuestList() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");

  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<"ACTIVE" | "INACTIVE" | "">("ACTIVE");
  const [guests, setGuests] = useState<GuestPlayer[]>([]);
  const [listLoading, setListLoading] = useState(false);

  const [addOpen, setAddOpen] = useState(false);
  const [selectedGuest, setSelectedGuest] = useState<GuestPlayer | null>(null);

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

  useEffect(() => {
    if (!facilityId) return;
    let cancelled = false;
    setListLoading(true);
    const timeout = setTimeout(() => {
      (async () => {
        const results =
          query.trim().length >= 2
            ? await getGuestService().searchGuests(facilityId, query)
            : await getGuestService().listGuests(facilityId, { status: statusFilter || undefined });
        if (!cancelled) {
          setGuests(results);
          setListLoading(false);
        }
      })();
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(timeout);
    };
  }, [facilityId, query, statusFilter]);

  function upsertGuest(guest: GuestPlayer) {
    setGuests((prev) => {
      const exists = prev.some((g) => g.id === guest.id);
      return exists ? prev.map((g) => (g.id === guest.id ? guest : g)) : [guest, ...prev];
    });
  }

  if (loadState === "loading") {
    return (
      <div className="space-y-3">
        <Skeleton className="h-11 w-full rounded-md" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }
  if (loadState === "none") {
    return <p className="text-sm text-muted-foreground">Complete your facility setup before managing guest players.</p>;
  }
  if (loadState === "error" || !facilityId) {
    return <p className="text-sm text-muted-foreground">Unable to load guest players. Please try again.</p>;
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-1 gap-2">
          <input
            aria-label="Search guests"
            placeholder="Search by name or phone"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="h-11 w-full max-w-sm rounded-md border border-input bg-secondary/60 px-3 text-sm"
          />
          <select
            aria-label="Status filter"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value as "ACTIVE" | "INACTIVE" | "")}
            className="h-11 rounded-md border border-input bg-secondary/60 px-3 text-sm"
          >
            <option value="ACTIVE">Active</option>
            <option value="INACTIVE">Inactive</option>
            <option value="">All</option>
          </select>
        </div>
        <Button type="button" onClick={() => setAddOpen(true)}>
          + Add Guest
        </Button>
      </div>

      {listLoading ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : guests.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
          {query.trim().length >= 2 ? "No guest players found." : "No guest players have been added yet."}
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border">
          <table className="w-full text-sm">
            <thead className="bg-secondary/50 text-left text-xs text-muted-foreground">
              <tr>
                <th className="p-3">Name</th>
                <th className="p-3">Phone</th>
                <th className="p-3">Status</th>
                <th className="p-3">Updated</th>
              </tr>
            </thead>
            <tbody>
              {guests.map((g) => (
                <tr
                  key={g.id}
                  className="cursor-pointer border-t border-border hover:bg-accent"
                  onClick={() => setSelectedGuest(g)}
                >
                  <td className="p-3 font-medium">{g.name}</td>
                  <td className="p-3 text-muted-foreground">{g.phone ?? "—"}</td>
                  <td className="p-3 text-muted-foreground">{g.status === "ACTIVE" ? "Active" : "Inactive"}</td>
                  <td className="p-3 text-muted-foreground">{new Date(g.updatedAt).toLocaleDateString("en-IN", { day: "numeric", month: "short" })}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <GuestFormDialog open={addOpen} onOpenChange={setAddOpen} facilityId={facilityId} onSaved={upsertGuest} />
      <GuestProfileDialog
        open={selectedGuest !== null}
        onOpenChange={(open) => !open && setSelectedGuest(null)}
        facilityId={facilityId}
        guest={selectedGuest}
        onChanged={(g) => {
          upsertGuest(g);
          setSelectedGuest(g);
        }}
      />
    </div>
  );
}