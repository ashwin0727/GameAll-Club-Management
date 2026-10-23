"use client";

import { useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useSportFilter } from "@/features/facility/hooks/use-sport-filter";
import { useGuestHistory } from "@/features/bookings/hooks/use-guest-booking-stats";
import { phoneKey } from "@/features/bookings/guest-insights";
import { getGuestService } from "@/services/guests";
import type { GuestPlayer } from "@/features/guests/types";
import { GuestFormDialog } from "@/features/guests/components/guest-form-dialog";
import { GuestProfileDialog } from "@/features/guests/components/guest-profile-dialog";
import { DropdownSelect } from "@/components/shared/dropdown-select";
import { EditOnly } from "@/features/access/edit-only";

export function GuestList() {
  const { data: facility, isLoading: facilityLoading, isError: facilityError } = useFacility();
  const facilityId = facility?.id ?? null;
  const loadState: "loading" | "ready" | "none" | "error" = facilityLoading
    ? "loading"
    : facilityError
      ? "error"
      : facility
        ? "ready"
        : "none";

  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<"ACTIVE" | "INACTIVE" | "">("ACTIVE");
  const [allGuests, setGuests] = useState<GuestPlayer[]>([]);
  const [listLoading, setListLoading] = useState(false);

  // The sports ticked in the top bar. Under All Sports every guest shows; with a subset, only the guests who have
  // booked one of those sports (guests themselves have no sport — what they have played is their booking history).
  const sportFilter = useSportFilter(facilityId);
  const sportIds = useMemo(() => (sportFilter.sportSet ? [...sportFilter.sportSet] : null), [sportFilter.sportSet]);
  const history = useGuestHistory(facilityId, sportIds, sportFilter.ready && sportIds !== null);
  const playedKeys = useMemo(
    () => (sportIds && history.data ? new Set(history.data.map((r) => phoneKey(r.guestPhone)).filter((k): k is string => k !== null)) : null),
    [sportIds, history.data],
  );
  const guests = useMemo(
    () => (sportIds ? (playedKeys ? allGuests.filter((g) => {
      const k = phoneKey(g.phone);
      return k !== null && playedKeys.has(k);
    }) : []) : allGuests),
    [sportIds, playedKeys, allGuests],
  );
  const sportLoading = sportIds !== null && history.isLoading;

  const [addOpen, setAddOpen] = useState(false);
  const [selectedGuest, setSelectedGuest] = useState<GuestPlayer | null>(null);

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
            aria-label="Search Guests"
            placeholder="Search by name or phone"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="h-11 w-full max-w-sm rounded-md border border-input bg-secondary/60 px-3 text-sm"
          />
          <DropdownSelect
            aria-label="Status Filter"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value as "ACTIVE" | "INACTIVE" | "")}
            className="h-11 rounded-md border border-input bg-secondary/60 px-3 text-sm"
          >
            <option value="ACTIVE">Active</option>
            <option value="INACTIVE">Inactive</option>
            <option value="">All</option>
          </DropdownSelect>
        </div>
        <EditOnly>
          <Button type="button" onClick={() => setAddOpen(true)}>
            + Add Guest
          </Button>
        </EditOnly>
      </div>

      {listLoading || sportLoading ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : guests.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
          {query.trim().length >= 2
            ? "No guest players found."
            : sportIds
              ? "No guest players have booked the selected sports."
              : "No guest players have been added yet."}
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