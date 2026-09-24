"use client";

import { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import { useRouter } from "next/navigation";
import { format } from "date-fns";
import { ChevronLeft, ChevronRight, Download, Search, X } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { Card } from "@/components/ui/card";
import { addDays, computeUtilization, filterEvents, startOfWeek } from "@/features/bookings/calendar-events";
import {
  collectedMinor,
  countGuestBookings,
  countGuestEvents,
  daysBetween,
  listKindToEventKind,
  percentDelta,
  pointsDelta,
} from "@/features/bookings/booking-stats";
import { BookingStatsRow } from "@/features/bookings/components/booking-stats-row";
import { dayForCourt, useCalendarEventsForRange } from "@/features/bookings/hooks/use-booking-calendar-data";
import { parseLocalDate } from "@/features/bookings/list-sources";
import type { OperatingSchedule } from "@/features/operating-hours/types";
import { useBookingsList } from "@/features/bookings/hooks/use-bookings-list";
import { DateRangePicker } from "@/features/bookings/components/date-range-picker";
import { SelectField } from "@/components/shared/select-field";
import { BookingRowActions } from "@/features/bookings/components/booking-row-actions";
import {
  BookingTable,
  PAGE_SIZES,
} from "@/features/bookings/components/booking-table";
import {
  ICON_BTN,
  SELECT,
} from "@/features/bookings/components/booking-toolbar";
import {
  bookingsToCsv,
  filterRows,
  paginate,
  sortRows,
  type BookingRow,
  type ListFilters,
  type SortDir,
  type SortKey,
} from "@/features/bookings/list-utils";
import type { Booking } from "@/features/bookings/types";
import { formatCurrency } from "@/features/pricing/money";
import { cn } from "@/lib/utils";

const iso = (d: Date) => format(d, "yyyy-MM-dd");

function download(filename: string, text: string) {
  const url = URL.createObjectURL(
    new Blob([`\uFEFF${text}`], { type: "text/csv;charset=utf-8" }),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * The List View tab: date range, court / type / status filters,
 * search (name, phone, reference), export, and the table with sorting,
 * selection, bulk actions and paging. Cancelling stays one booking at a time in
 * the details dialog — a cancellation can trigger a refund, so it is
 * deliberately not a bulk action.
 */
export function BookingListTab({
  facilityId,
  courts,
  courtName,
  onOpenBooking,
  onChanged,
  schedules,
  activeMembers,
  refreshKey,
  toolbarSlot,
}: {
  facilityId: string;
  courts: { id: string; name: string }[];
  courtName: (courtId: string) => string;
  onOpenBooking: (booking: Booking, mode?: "view" | "reschedule") => void;
  /** A row action changed a booking, so the page refreshes everything that shows it. */
  onChanged: () => void;
  /** Each court's opening hours — utilization is measured against them. */
  schedules: Map<string, OperatingSchedule | null> | undefined;
  /** Facility-wide, so it doesn't follow the filters. */
  activeMembers: number | undefined;
  /** Bumped by the page after a booking changes, so the table refetches. */
  refreshKey: number;
  /** Where the filter row is drawn — a full-width strip above the table and side panels, like the calendar's. */
  toolbarSlot: HTMLElement | null;
}) {
  const [range, setRange] = useState(() => {
    const monday = startOfWeek(new Date());
    return { from: iso(monday), to: iso(addDays(monday, 6)) };
  });
  const [filters, setFilters] = useState<ListFilters>({
    courtId: "",
    kind: "",
    status: "",
    search: "",
  });
  const [sortKey, setSortKey] = useState<SortKey>("date");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(PAGE_SIZES[0]!);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [copied, setCopied] = useState(false);

  const router = useRouter();
  const list = useBookingsList(facilityId, range.from, range.to, courts);
  const { refetch } = list;
  useEffect(() => {
    if (refreshKey > 0) void refetch();
  }, [refreshKey, refetch]);

  const courtIds = useMemo(() => new Set(courts.map((c) => c.id)), [courts]);

  const filtered = useMemo(() => {
    const base = (list.data ?? []).filter(
      (r) =>
        // Memberships and coaching may not name a court at all; keep those, and drop rows on another sport's courts.
        r.courtIds.length === 0 || r.courtIds.some((id) => courtIds.has(id)),
    );
    return sortRows(filterRows(base, filters), sortKey, sortDir, courtName);
    // courtName is a fresh closure each render; the data it reads is covered by courtIds/list.data.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [list.data, courtIds, filters, sortKey, sortDir]);

  const paged = paginate(filtered, page, perPage);

  // Any change to what is listed puts you back on page one and drops selections that are no longer visible.
  useEffect(() => {
    setPage(1);
  }, [filters, range, sortKey, sortDir, perPage]);
  useEffect(() => {
    setSelected((prev) => {
      const visible = new Set(filtered.map((r) => r.id));
      const next = new Set([...prev].filter((id) => visible.has(id)));
      return next.size === prev.size ? prev : next;
    });
  }, [filtered]);

  function shiftRange(direction: 1 | -1) {
    const from = new Date(`${range.from}T00:00:00`);
    const to = new Date(`${range.to}T00:00:00`);
    const days = Math.round((to.getTime() - from.getTime()) / 86_400_000) + 1;
    setRange({
      from: iso(addDays(from, days * direction)),
      to: iso(addDays(to, days * direction)),
    });
  }

  function onSort(key: SortKey) {
    if (key === sortKey) setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    else {
      setSortKey(key);
      setSortDir("asc");
    }
  }

  const amountText = (r: BookingRow) =>
    r.amountMinor === null ? "" : formatCurrency(r.amountMinor, r.currency);
  const selectedRows = filtered.filter((r) => selected.has(r.id));

  function exportRows(rows: BookingRow[], suffix: string) {
    download(
      `bookings-${range.from}_to_${range.to}${suffix}.csv`,
      bookingsToCsv(rows, courtName, amountText),
    );
  }

  async function copyReferences() {
    try {
      await navigator.clipboard.writeText(
        selectedRows.map((r) => r.reference).join("\n"),
      );
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      /* clipboard blocked — nothing to do */
    }
  }

  // ── The cards under the table: they follow the date range and every filter ──
  // Utilization needs the calendar's events for this same range (bookings, membership
  // sessions, coaching, maintenance), and measures them against each day's opening hours.
  const rangeStart = parseLocalDate(range.from);
  const rangeLastDay = parseLocalDate(range.to);
  const rangeEvents = useCalendarEventsForRange(facilityId, rangeStart, addDays(rangeLastDay, 1));
  // The stretch of the same length just before this one, for the "vs previous range" line.
  const rangeLength = daysBetween(rangeStart, rangeLastDay).length;
  const prevStart = addDays(rangeStart, -rangeLength);
  const prevEvents = useCalendarEventsForRange(facilityId, prevStart, rangeStart);

  const stats = useMemo(() => {
    const cancelledOnly = filters.status === "cancelled";
    const scoped = (rangeEvents.data ?? []).filter((e) => courtIds.has(e.courtId));
    // A cancelled booking isn't on the calendar, so filtering to cancelled leaves nothing occupying a court.
    const events = cancelledOnly
      ? []
      : filterEvents(scoped, {
          courtId: filters.courtId,
          kind: listKindToEventKind(filters.kind),
          status: filters.status === "cancelled" ? "" : filters.status,
        });
    const statsCourts = filters.courtId ? [filters.courtId] : [...courtIds];
    const u = computeUtilization(events, statsCourts, daysBetween(rangeStart, rangeLastDay), (courtId, date) =>
      dayForCourt(schedules, courtId, date),
    );
    const guestBookings = countGuestBookings(filtered, cancelledOnly);

    // The previous range is measured from the calendar's events, so it only lines up with this range's
    // figure when the filters are ones the calendar knows about — no text search, and not "cancelled".
    let guestDelta = null;
    let utilizationDelta = null;
    if (prevEvents.data && !cancelledOnly && filters.search.trim() === "") {
      const before = filterEvents(prevEvents.data.filter((e) => courtIds.has(e.courtId)), {
        courtId: filters.courtId,
        kind: listKindToEventKind(filters.kind),
        status: filters.status === "cancelled" ? "" : filters.status,
      });
      guestDelta = percentDelta(guestBookings, countGuestEvents(before, prevStart, rangeStart), "vs previous range");
      const prevU = computeUtilization(before, statsCourts, daysBetween(prevStart, addDays(rangeStart, -1)), (courtId, date) =>
        dayForCourt(schedules, courtId, date),
      );
      utilizationDelta = pointsDelta(u.exactPercent, prevU.exactPercent, "vs previous range");
    }

    return {
      ...u,
      guestBookings,
      guestDelta,
      utilizationDelta,
      revenueInr: collectedMinor(filtered) / 100,
      courtsInScope: statsCourts.length,
    };
    // rangeStart / rangeLastDay are rebuilt from range each render; range itself is the dependency.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rangeEvents.data, prevEvents.data, courtIds, filters, filtered, range, schedules]);

  const chip = cn(SELECT, "px-[14px]");

  const toolbar = (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-3">
      <DateRangePicker
        from={range.from}
        to={range.to}
        onChange={(from, to) => setRange({ from, to })}
        align="left"
        fullLabel
        triggerClassName={cn(
          chip,
          "flex items-center gap-2 whitespace-nowrap font-medium tabular-nums",
        )}
      />
      <button
        type="button"
        aria-label="Previous range"
        onClick={() => shiftRange(-1)}
        className={ICON_BTN}
      >
        <ChevronLeft className="h-4 w-4" />
      </button>
      <button
        type="button"
        aria-label="Next range"
        onClick={() => shiftRange(1)}
        className={ICON_BTN}
      >
        <ChevronRight className="h-4 w-4" />
      </button>
      <SelectField
        wrapperClassName="w-[140px]"
        ariaLabel="Court"
        value={filters.courtId}
        onValueChange={(v) => setFilters((f) => ({ ...f, courtId: v }))}
        options={[
          { value: "", label: "All Courts" },
          ...courts.map((c) => ({ value: c.id, label: c.name })),
        ]}
        className={SELECT}
      />
      <SelectField
        wrapperClassName="w-[172px]"
        ariaLabel="Booking type"
        value={filters.kind}
        onValueChange={(v) =>
          setFilters((f) => ({ ...f, kind: v as ListFilters["kind"] }))
        }
        options={[
          { value: "", label: "All Booking Types" },
          { value: "GUEST", label: "Guest" },
          { value: "MEMBERSHIP", label: "Membership" },
          { value: "COACHING", label: "Coaching" },
          { value: "EVENT", label: "Event" },
        ]}
        className={SELECT}
      />
      <SelectField
        wrapperClassName="w-[140px]"
        ariaLabel="Status"
        value={filters.status}
        onValueChange={(v) =>
          setFilters((f) => ({ ...f, status: v as ListFilters["status"] }))
        }
        options={[
          { value: "", label: "All Status" },
          { value: "confirmed", label: "Confirmed" },
          { value: "pending", label: "Pending" },
          { value: "completed", label: "Completed" },
          { value: "cancelled", label: "Cancelled" },
        ]}
        className={SELECT}
      />
      <div className="relative min-w-[200px] flex-1">
        <Search
          className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground"
          aria-hidden
        />
        <input
          type="text"
          aria-label="Search bookings"
          placeholder="Search by member, phone, or reference…"
          value={filters.search}
          onChange={(e) =>
            setFilters((f) => ({ ...f, search: e.target.value }))
          }
          className={cn(
            SELECT,
            "w-full pl-10 pr-9 placeholder:text-muted-foreground",
          )}
        />
        {filters.search && (
          <button
            type="button"
            aria-label="Clear search"
            onClick={() => setFilters((f) => ({ ...f, search: "" }))}
            className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded p-1 text-muted-foreground hover:text-foreground"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
      <button
        type="button"
        onClick={() => exportRows(filtered, "")}
        disabled={filtered.length === 0}
        className={cn(
          SELECT,
          "flex items-center gap-2 px-4 font-medium hover:bg-accent disabled:opacity-50",
        )}
      >
        <Download className="h-4 w-4" aria-hidden />
        Export
      </button>
    </div>
  );

  return (
    <>
      {toolbarSlot && createPortal(toolbar, toolbarSlot)}
      <Card className="overflow-visible">
        {/* Bulk actions — only while something is selected */}
        {selectedRows.length > 0 && (
          <div className="mx-4 mb-3 flex flex-wrap items-center gap-3 rounded-[8px] bg-primary/10 px-3 py-2 text-sm">
            <span className="font-medium">{selectedRows.length} selected</span>
            <button
              type="button"
              onClick={() => exportRows(selectedRows, "-selected")}
              className="font-medium text-primary hover:underline"
            >
              Export selected
            </button>
            <button
              type="button"
              onClick={copyReferences}
              className="font-medium text-primary hover:underline"
            >
              {copied ? "Copied!" : "Copy references"}
            </button>
            <button
              type="button"
              onClick={() => setSelected(new Set())}
              className="ml-auto text-muted-foreground hover:text-foreground"
            >
              Clear selection
            </button>
          </div>
        )}

        {/* Table */}
        <div
          className={cn(
            "transition-opacity",
            list.isPlaceholderData && "opacity-60",
          )}
        >
          {list.isLoading ? (
            <div className="space-y-2 p-4">
              {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-12 w-full rounded-md" />
              ))}
            </div>
          ) : list.isError ? (
            <p className="px-4 py-14 text-center text-sm text-muted-foreground">
              Unable to load bookings. Please try again.
            </p>
          ) : (
            <BookingTable
              rows={paged.rows}
              total={filtered.length}
              sortKey={sortKey}
              sortDir={sortDir}
              onSort={onSort}
              selected={selected}
              onToggle={(id) =>
                setSelected((prev) => {
                  const next = new Set(prev);
                  if (next.has(id)) next.delete(id);
                  else next.add(id);
                  return next;
                })
              }
              onTogglePage={(checked) =>
                setSelected((prev) => {
                  const next = new Set(prev);
                  for (const r of paged.rows) {
                    if (checked) next.add(r.id);
                    else next.delete(r.id);
                  }
                  return next;
                })
              }
              courtName={courtName}
              // A court booking opens its details; a membership or coaching row opens the page that owns it.
              onOpen={(r) => (r.booking ? onOpenBooking(r.booking) : r.href ? router.push(r.href) : undefined)}
            renderActions={(r) => (
              <BookingRowActions
                row={r}
                courts={courts}
                onOpenBooking={onOpenBooking}
                onChanged={onChanged}
              />
            )}
              page={paged.page}
              pages={paged.pages}
              perPage={perPage}
              onPage={setPage}
              onPerPage={setPerPage}
              emptyText={
                filters.kind === "EVENT"
                  ? "No events yet — events aren't recorded in this range."
                  : "No bookings match these filters."
              }
            />
          )}
        </div>
      </Card>

      <BookingStatsRow
        totalGuestBookings={stats.guestBookings}
        guestSub="In the selected range"
        guestDelta={stats.guestDelta}
        activeMembers={activeMembers}
        utilizationPercent={stats.exactPercent}
        courtsActive={stats.activeCourts}
        courtsTotal={stats.courtsInScope}
        utilizationDelta={stats.utilizationDelta}
        revenueInr={stats.revenueInr}
        revenueSub="For the selected range & filters"
      />
    </>
  );
}
