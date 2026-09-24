"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { ChevronRight as Crumb } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { SelectField } from "@/components/shared/select-field";
import { DateRangePicker } from "@/features/bookings/components/date-range-picker";
import { MemberSelectField } from "@/features/memberships/components/member-select-field";
import { MemberScheduleGrid, type DayColumnData } from "@/features/memberships/components/member-schedule-grid";
import { MemberScheduleDetailsPanel } from "@/features/memberships/components/member-schedule-details-panel";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useActiveFacilitySportId } from "@/features/facility/hooks/use-active-facility-sport";
import { useMemberSchedules, usePlayingAreasList } from "@/features/memberships/hooks/use-member-schedule";
import { courtsForSport, scheduleRowsForSport } from "@/features/memberships/sport-scope";
import { useCalendarEventsForRange, useCourtSchedules, dayForCourt } from "@/features/bookings/hooks/use-booking-calendar-data";
import { addDays, startOfWeek } from "@/features/bookings/calendar-events";
import { windowsForDay } from "@/features/bookings/slots";
import { assignedCourtIds, blocksForDay, groupMemberSchedules, type OtherCourtEvent } from "@/features/memberships/member-schedule";
import { cn } from "@/lib/utils";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** Sampled from the Membership_Dashboard.png artwork's own pale-mint backdrop — same value the
 *  Add Member wizard's hero uses, so the panel and the image read as one surface. */
const PANEL_TINT = "#EAF9F1";

function dateLabel(d: Date): string {
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

function rangeLabel(days: Date[]): string {
  if (days.length <= 1) return dateLabel(days[0] ?? new Date());
  return `${dateLabel(days[0]!)} – ${dateLabel(days[days.length - 1]!)}`;
}

/** "2026-09-15" — local, not UTC, so a date typed/picked in the browser's own timezone lands
 *  on the day the user actually clicked. */
function isoOf(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function parseIsoLocal(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1);
}

/** Every date from `fromIso` to `toIso`, inclusive — the days actually drawn on the grid. */
function datesInRange(fromIso: string, toIso: string): Date[] {
  const start = parseIsoLocal(fromIso);
  const end = parseIsoLocal(toIso);
  const out: Date[] = [];
  for (let d = start; d <= end; d = addDays(d, 1)) out.push(d);
  return out;
}

// Same height/radius/border as the Date Range display and MemberSelectField, so all four
// filter fields in the row read as one consistent set.
const FIELD_CLASS =
  "h-10 rounded-[6px] border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30 focus-visible:border-foreground/40";

const VIEW_OPTIONS = [
  { value: "week", label: "Week" },
  { value: "day", label: "Day" },
];

/**
 * Manage Membership Schedule — pick a member, see their allocated court slots for the week
 * alongside guest bookings, maintenance blocks and closed days on the same court(s). Reuses the
 * booking calendar's own event pipeline (`useCalendarEventsForRange`) for the guest/maintenance
 * overlay and operating-hours logic, rather than re-deriving either.
 */
export function MemberSchedulePage() {
  const { data: facility } = useFacility();
  const facilityId = facility?.id ?? null;
  const activeSportId = useActiveFacilitySportId(facilityId);

  const [selectedMemberId, setSelectedMemberId] = useState<string | null>(null);
  const [courtFilter, setCourtFilter] = useState<string>("");
  const [view, setView] = useState<"week" | "day">("week");
  const [rangeFrom, setRangeFrom] = useState(() => isoOf(startOfWeek(new Date())));
  const [rangeTo, setRangeTo] = useState(() => isoOf(addDays(startOfWeek(new Date()), 6)));

  const schedulesQuery = useMemberSchedules(facilityId);
  const areasQuery = usePlayingAreasList(facilityId);
  // Scoped to the top bar's active sport — same rule as every other Membership v1 page.
  const members = useMemo(
    () => groupMemberSchedules(scheduleRowsForSport(schedulesQuery.data ?? [], activeSportId)),
    [schedulesQuery.data, activeSportId],
  );
  const areas = useMemo(() => courtsForSport(areasQuery.data ?? [], activeSportId), [areasQuery.data, activeSportId]);

  // Default to the first member with a schedule, once loaded.
  useEffect(() => {
    if (!selectedMemberId && members.length > 0) setSelectedMemberId(members[0]!.memberId);
  }, [members, selectedMemberId]);

  const selectedMember = members.find((m) => m.memberId === selectedMemberId) ?? null;
  const memberCourtIds = useMemo(() => (selectedMember ? assignedCourtIds(selectedMember.slots) : []), [selectedMember]);
  const visibleCourtIds = useMemo(() => (courtFilter ? [courtFilter] : memberCourtIds), [courtFilter, memberCourtIds]);

  // The Court filter defaults to the member's own (first) assigned court whenever the selected
  // member changes — a member's slot list, not a live subscription, so a ref avoids resetting a
  // manually-picked court back to the default on every unrelated re-render/refetch.
  const membersRef = useRef(members);
  useEffect(() => {
    membersRef.current = members;
  });
  useEffect(() => {
    const m = membersRef.current.find((x) => x.memberId === selectedMemberId);
    setCourtFilter(m ? (assignedCourtIds(m.slots)[0] ?? "") : "");
  }, [selectedMemberId]);

  function changeView(v: "week" | "day") {
    setView(v);
    if (v === "day") {
      setRangeTo(rangeFrom);
    } else {
      const monday = startOfWeek(parseIsoLocal(rangeFrom));
      setRangeFrom(isoOf(monday));
      setRangeTo(isoOf(addDays(monday, 6)));
    }
  }

  const days = useMemo(() => datesInRange(rangeFrom, rangeTo), [rangeFrom, rangeTo]);
  const from = parseIsoLocal(rangeFrom);
  const to = addDays(parseIsoLocal(rangeTo), 1);

  const eventsQuery = useCalendarEventsForRange(facilityId, from, to, visibleCourtIds.length > 0);
  const schedulesForCourts = useCourtSchedules(facilityId, areas);

  const otherEvents: OtherCourtEvent[] = useMemo(
    () =>
      (eventsQuery.data ?? [])
        .filter((e): e is typeof e & { kind: "GUEST" | "MAINTENANCE" } => e.kind === "GUEST" || e.kind === "MAINTENANCE")
        .map((e) => ({ courtId: e.courtId, start: e.start, end: e.end, kind: e.kind, title: e.title, subtitle: e.subtitle, href: e.href })),
    [eventsQuery.data],
  );

  const dayColumns: DayColumnData[] = useMemo(() => {
    return days.map((date) => {
      const closed =
        visibleCourtIds.length > 0 &&
        visibleCourtIds.every((courtId) => {
          const day = dayForCourt(schedulesForCourts.data, courtId, date);
          return !day || windowsForDay(day).length === 0;
        });
      const blocks = selectedMember
        ? blocksForDay(date, selectedMember.slots, otherEvents, visibleCourtIds, closed)
        : closed
          ? [{ kind: "CLOSED" as const, startTime: "00:00", endTime: "24:00", title: "Court Closed", subtitle: "" }]
          : [];
      return { date, blocks };
    });
  }, [days, selectedMember, otherEvents, visibleCourtIds, schedulesForCourts.data]);

  // Every active court, not just this member's own — they can still show up in someone else's
  // guest booking on a different court, and staff should be able to check that too. Defaults to
  // the member's own court via the effect above; this list is just what's pickable.
  const courtOptions = [
    { value: "", label: "All Courts" },
    ...areas.map((a) => ({ value: a.id, label: a.name })),
  ];
  const memberOptions = members.map((m) => ({ value: m.memberId, label: m.fullName, sublabel: m.phone }));

  const loading = schedulesQuery.isLoading || areasQuery.isLoading;

  return (
    <div className="space-y-4">
      {/* This exact structure — single element, two background layers (image + gradient), a
          separate feather div for the join, breadcrumb inside the title block — is copied
          verbatim from the Add Member wizard's hero (add-member-wizard-page.tsx), itself copied
          from the Membership Dashboard hero. Both are already live and confirmed correct. */}
      <div className="flex flex-col overflow-hidden rounded-2xl bg-card lg:h-[120px] lg:flex-row lg:items-stretch">
        <div className="flex min-w-0 flex-col justify-center gap-0.5 px-6 py-3 lg:w-[34%]">
          <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
            <Link href="/memberships/v1" className="hover:text-foreground">
              Membership
            </Link>
            <Crumb className="h-3.5 w-3.5" aria-hidden />
            <span className="font-medium text-foreground">Membership Schedule</span>
          </nav>
          <h1 className="mt-1 truncate text-2xl font-bold text-black dark:text-foreground">Manage Membership Schedule</h1>
          <p className="line-clamp-2 text-sm text-muted-foreground">
            View and manage a member&apos;s court schedule, assign time slots, make changes or cancel slots.
          </p>
        </div>

        {/* Hidden on mobile/tablet — decorative only; desktop (lg+) is unaffected. */}
        <div
          className="relative hidden flex-1 items-center gap-4 px-6 lg:flex"
          style={{
            backgroundImage: `url(/assets/Membership_Dashboard.png), linear-gradient(to right, hsl(var(--card)) 0%, ${PANEL_TINT} 22%, ${PANEL_TINT} 100%)`,
            backgroundSize: "74%, 100% 100%",
            backgroundPosition: "right 12px center, left center",
            backgroundRepeat: "no-repeat, no-repeat",
          }}
        >
          {/* Feathers the artwork's left edge into the tint. Transparent at the very left so it
              never repaints the join with the title block. */}
          <div
            aria-hidden
            className="pointer-events-none absolute inset-y-0 left-0 w-[62%]"
            style={{
              backgroundImage: `linear-gradient(to right, transparent 0%, ${PANEL_TINT} 14%, ${PANEL_TINT} 40%, transparent 100%)`,
            }}
          />

          <div className="relative z-10 min-w-0 max-w-[46%]" style={{ marginLeft: "20%" }}>
            <p className="text-[15px] font-bold leading-snug text-black">Well Scheduled. Better Play.</p>
            <p className="mt-1 text-xs text-black/70">Keep your members active with a smooth and flexible schedule.</p>
          </div>
        </div>
      </div>

      {loading ? (
        <Skeleton className="h-96 w-full rounded-xl" />
      ) : (
        <>
          <div className="flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-3">
            <div className="w-full sm:w-64">
              <p className="mb-1 text-xs font-medium text-foreground/80">Select Member</p>
              <MemberSelectField
                value={selectedMemberId ?? ""}
                onValueChange={setSelectedMemberId}
                options={memberOptions}
                ariaLabel="Select member"
              />
            </div>
            <div className="w-full sm:w-56">
              <p className="mb-1 text-xs font-medium text-foreground/80">Date Range</p>
              <DateRangePicker
                from={rangeFrom}
                to={rangeTo}
                onChange={(f, t) => {
                  setRangeFrom(f);
                  setRangeTo(t);
                }}
                fullLabel
                triggerClassName={cn("flex w-full items-center gap-2", FIELD_CLASS)}
              />
            </div>
            <div className="w-[calc(50%-0.375rem)] sm:w-32">
              <p className="mb-1 text-xs font-medium text-foreground/80">View By</p>
              <SelectField value={view} onValueChange={(v) => changeView(v as "week" | "day")} options={VIEW_OPTIONS} ariaLabel="View by" className={FIELD_CLASS} />
            </div>
            <div className="w-[calc(50%-0.375rem)] sm:w-44">
              <p className="mb-1 text-xs font-medium text-foreground/80">Court</p>
              <SelectField
                value={courtFilter}
                onValueChange={setCourtFilter}
                options={courtOptions}
                ariaLabel="Court filter"
                className={FIELD_CLASS}
              />
            </div>
          </div>

          <div className="grid grid-cols-1 gap-4 xl:grid-cols-[1fr_300px]">
            <Card className="space-y-3 rounded-xl p-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="text-sm font-bold text-black dark:text-foreground">{days.length > 1 ? "Weekly Schedule" : "Daily Schedule"}</p>
                  <p className="text-xs text-muted-foreground">{rangeLabel(days)}</p>
                </div>
                <div className="flex flex-wrap items-center gap-3 text-[11px] text-muted-foreground">
                  <span className="flex items-center gap-1">
                    <span className="h-2.5 w-2.5 rounded-full bg-success" aria-hidden /> Member Slot
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="h-2.5 w-2.5 rounded-full bg-blue-500" aria-hidden /> Guest Booking
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="h-2.5 w-2.5 rounded-full bg-muted-foreground/50" aria-hidden /> Blocked / Maintenance
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="h-2.5 w-2.5 rounded-full bg-destructive/40" aria-hidden /> Unavailable
                  </span>
                </div>
              </div>

              {!selectedMember ? (
                <div className="rounded-lg border border-border p-8 text-center text-sm text-muted-foreground">
                  No members have a dedicated court schedule yet.
                </div>
              ) : (
                <MemberScheduleGrid days={dayColumns} today={new Date()} />
              )}
            </Card>

            {selectedMember && <MemberScheduleDetailsPanel member={selectedMember} />}
          </div>
        </>
      )}
    </div>
  );
}
