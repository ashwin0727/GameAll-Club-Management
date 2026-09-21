"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useUiStore } from "@/stores/ui-store";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import {
  computeAvailableSlots,
  windowsForDay,
} from "@/features/bookings/slots";
import {
  computeUtilization,
  daysInRange,
  eventsOnDay,
  isSameDay,
  rangeFor,
  shiftAnchor,
  type CalEvent,
  type CalEventKind,
  type CalView,
} from "@/features/bookings/calendar-events";
import { computeGridHours } from "@/features/bookings/calendar-layout";
import { countGuestEvents, percentDelta, pointsDelta } from "@/features/bookings/booking-stats";
import {
  dayForCourt,
  useBookingCalendarData,
  useBookingFacilityStats,
  useCalendarEventsForRange,
  useCourtSchedules,
  usePeriodRevenue,
} from "@/features/bookings/hooks/use-booking-calendar-data";
import type { Booking, TimeSlot } from "@/features/bookings/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { MembershipSessionSlot } from "@/features/membership-sessions/types";
import { BookingDialog } from "@/features/bookings/components/booking-dialog";
import { BookingDetailsDialog } from "@/features/bookings/components/booking-details-dialog";
import { MembershipSlotCard } from "@/features/membership-sessions/components/membership-slot-card";
import { BookingToolbar } from "@/features/bookings/components/booking-toolbar";
import {
  BookingTimeGrid,
  type GridColumn,
} from "@/features/bookings/components/booking-time-grid";
import { BookingMonthGrid } from "@/features/bookings/components/booking-month-grid";
import { BookingListTab } from "@/features/bookings/components/booking-list-tab";
import { BookingStatsRow } from "@/features/bookings/components/booking-stats-row";
import { BookingAgenda } from "@/features/bookings/components/booking-agenda";
import { CalendarLegendBar } from "@/features/bookings/components/calendar-legend-bar";
import { cn } from "@/lib/utils";

type TabKey = "court" | "list";

const TABS: { key: TabKey; label: string }[] = [
  { key: "court", label: "Court View" },
  { key: "list", label: "List View" },
];

const PERIOD_NOUN: Record<CalView, string> = {
  day: "On this day",
  week: "This week",
  month: "This month",
  agenda: "This month",
};

export function BookingOperationsView() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const {
    data: facility,
    isLoading: facilityLoading,
    isError: facilityError,
  } = useFacility();
  const facilityId = facility?.id ?? null;
  const activeSportId = useUiStore((s) => s.activeFacilitySportId);

  const [loadState, setLoadState] = useState<
    "loading" | "ready" | "none" | "error"
  >("loading");
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);

  const [tab, setTab] = useState<TabKey>("court");
  const [listRefresh, setListRefresh] = useState(0);
  // DOM slot for the list tabs' filter row (rendered into by BookingListTab via a portal).
  const [toolbarSlot, setToolbarSlot] = useState<HTMLElement | null>(null);
  const [view, setView] = useState<CalView>("day");
  const [anchor, setAnchor] = useState(() => new Date());
  const [courtFilter, setCourtFilter] = useState("");
  // The legend's switches: a type in this set is left off the calendar (and out of the cards).
  const [hiddenKinds, setHiddenKinds] = useState<ReadonlySet<CalEventKind>>(new Set());

  const [bookingDialog, setBookingDialog] = useState<{
    courtId?: string;
    slot?: TimeSlot;
    date?: Date;
  } | null>(null);
  const [detailsBooking, setDetailsBooking] = useState<Booking | null>(null);
  const [detailsMode, setDetailsMode] = useState<"view" | "reschedule">("view");
  const [membershipSlotDialog, setMembershipSlotDialog] =
    useState<MembershipSessionSlot | null>(null);

  useEffect(() => {
    if (facilityLoading) return;
    if (facilityError) {
      setLoadState("error");
      return;
    }
    if (!facility) {
      setLoadState("none");
      return;
    }
    let cancelled = false;
    (async () => {
      const [fs, allSports, playingAreas] = await Promise.all([
        getSportsService().getFacilitySports(facility.id),
        getSportsService().getActiveSports(),
        getPlayingAreasService().getPlayingAreas(facility.id),
      ]);
      if (cancelled) return;
      setFacilitySports(fs.filter((s) => s.enabled));
      setSports(allSports);
      setAreas(
        playingAreas.filter(
          (a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled,
        ),
      );
      setLoadState("ready");
    })().catch(() => setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, [facility, facilityLoading, facilityError]);

  // One sport at a time: whatever the top bar picked, else the first sport.
  const facilitySport =
    facilitySports.find((fs) => fs.id === activeSportId) ?? facilitySports[0];
  const sportCourts = useMemo(
    () =>
      facilitySport
        ? areas.filter((a) => a.facilitySportId === facilitySport.id)
        : [],
    [areas, facilitySport],
  );
  const courtIds = useMemo(
    () => new Set(sportCourts.map((c) => c.id)),
    [sportCourts],
  );
  const courtName = (id: string) =>
    areas.find((a) => a.id === id)?.name ?? "Court";
  // Court 1 before Court 2: the order the courts are configured in.
  const courtOrder = (id: string) => {
    const i = sportCourts.findIndex((c) => c.id === id);
    return i < 0 ? sportCourts.length : i;
  };

  const ready = loadState === "ready";
  const calendar = useBookingCalendarData(
    facilityId,
    view,
    anchor,
    ready,
  );
  const schedules = useCourtSchedules(facilityId, areas);
  const facilityStats = useBookingFacilityStats(facilityId);
  const period = rangeFor(view, anchor);
  const periodRevenue = usePeriodRevenue(facilityId, period.from, period.to);

  const now = new Date();
  const days = useMemo(() => daysInRange(view, anchor), [view, anchor]);

  const sportEvents = useMemo(
    () => (calendar.data ?? []).filter((e) => courtIds.has(e.courtId)),
    [calendar.data, courtIds],
  );
  const shown = useMemo(
    () => sportEvents.filter((e) => (!courtFilter || e.courtId === courtFilter) && !hiddenKinds.has(e.kind)),
    [sportEvents, courtFilter, hiddenKinds],
  );

  // The cards follow the toolbar and legend: the visible period, the court filter and the
  // types left switched on. Utilization is booked time over the opening hours of every day in
  // the period (24 h a day where the facility said so), for the courts in view. Each card also
  // compares with the period just before (the previous day / week / month).
  const prevAnchor = shiftAnchor(view, anchor, -1);
  const prevPeriod = rangeFor(view, prevAnchor);
  const prevEvents = useCalendarEventsForRange(facilityId, prevPeriod.from, prevPeriod.to, ready);
  const prevRevenue = usePeriodRevenue(facilityId, prevPeriod.from, prevPeriod.to);
  const versus = view === "day" ? "vs previous day" : view === "week" ? "vs last week" : "vs last month";

  const stats = useMemo(() => {
    const dayFor = (courtId: string, date: Date) => dayForCourt(schedules.data, courtId, date);
    const statsCourts = courtFilter ? [courtFilter] : [...courtIds];
    const visible = (events: CalEvent[]) =>
      events.filter((e) => courtIds.has(e.courtId) && (!courtFilter || e.courtId === courtFilter) && !hiddenKinds.has(e.kind));
    const u = computeUtilization(shown, statsCourts, days, dayFor);
    // Month loads the neighbouring months' days too; only the visible period counts.
    const { from, to } = rangeFor(view, anchor);
    const guestBookings = countGuestEvents(shown, from, to);

    let guestDelta = null;
    let utilizationDelta = null;
    if (prevEvents.data) {
      const before = visible(prevEvents.data);
      guestDelta = percentDelta(guestBookings, countGuestEvents(before, prevPeriod.from, prevPeriod.to), versus);
      const prevU = computeUtilization(before, statsCourts, daysInRange(view, prevAnchor), dayFor);
      utilizationDelta = pointsDelta(u.exactPercent, prevU.exactPercent, versus);
    }
    return { ...u, guestBookings, guestDelta, utilizationDelta };
    // prevPeriod is rebuilt from prevAnchor each render; prevAnchor changes with view / anchor.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shown, courtIds, courtFilter, hiddenKinds, days, schedules.data, view, anchor, prevEvents.data, versus]);
  const revenueDelta =
    periodRevenue.data !== undefined && prevRevenue.data !== undefined
      ? percentDelta(periodRevenue.data, prevRevenue.data, versus)
      : null;
  function reloadAll() {
    queryClient.invalidateQueries({ queryKey: ["booking-calendar"] });
    queryClient.invalidateQueries({ queryKey: ["booking-facility-stats"] });
    queryClient.invalidateQueries({ queryKey: ["booking-list"] });
    queryClient.invalidateQueries({ queryKey: ["booking-calendar-range"] });
    queryClient.invalidateQueries({ queryKey: ["booking-period-revenue"] });
    setListRefresh((n) => n + 1);
  }

  // Keep an open membership-slot dialog's numbers live after a
  // release/restore/guest-book reloads the data.
  useEffect(() => {
    if (!membershipSlotDialog) return;
    const fresh = (calendar.data ?? []).find(
      (e) =>
        e.membershipSlot?.batchId === membershipSlotDialog.batchId &&
        e.membershipSlot?.sessionDate === membershipSlotDialog.sessionDate &&
        e.membershipSlot?.courtId === membershipSlotDialog.courtId,
    )?.membershipSlot;
    if (fresh) setMembershipSlotDialog(fresh);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [calendar.data]);

  function handleEventClick(e: CalEvent) {
    if (e.booking) setDetailsBooking(e.booking);
    else if (e.membershipSlot) setMembershipSlotDialog(e.membershipSlot);
    else if (e.href) router.push(e.href);
  }

  function pickDay(day: Date) {
    setAnchor(day);
    setView("day");
    setTab("court");
  }

  /** A click on empty time in the Day grid: open the booking dialog on that hour if it's genuinely free. */
  function handleEmptyClick(col: GridColumn, minuteOfDay: number) {
    const court = col.key;
    const day = dayForCourt(schedules.data, court, col.day);
    if (!day) return;
    const courtEvents = sportEvents.filter((e) => e.courtId === court);
    const bookings = courtEvents.flatMap((e) => (e.booking ? [e.booking] : []));
    const slot = computeAvailableSlots(col.day, day, bookings).find((s) => {
      const start = new Date(s.startTime);
      const startMin = start.getHours() * 60 + start.getMinutes();
      return minuteOfDay >= startMin && minuteOfDay < startMin + 60;
    });
    if (!slot?.available) return;
    const s = new Date(slot.startTime);
    const en = new Date(slot.endTime);
    const blocker = courtEvents.find((e) => e.start < en && s < e.end);
    if (blocker) {
      if (blocker.membershipSlot)
        setMembershipSlotDialog(blocker.membershipSlot);
      return;
    }
    setBookingDialog({ courtId: court, slot, date: col.day });
  }

  if (loadState === "loading") {
    return (
      <div className="space-y-4">
        <Skeleton className="h-10 w-72 rounded-md" />
        <Skeleton className="h-[480px] w-full rounded-xl" />
      </div>
    );
  }
  if (loadState === "none") {
    return (
      <p className="text-sm text-muted-foreground">
        Complete your facility setup before taking bookings.
      </p>
    );
  }
  if (loadState === "error") {
    return (
      <p className="text-sm text-muted-foreground">
        Unable to load bookings. Please try again.
      </p>
    );
  }

  const visibleCourts = courtFilter
    ? sportCourts.filter((c) => c.id === courtFilter)
    : sportCourts;

  // ---- Grid columns ---------------------------------------------------
  let columns: GridColumn[] = [];
  let hours = { startHour: 6, endHour: 22 };
  if (view === "day") {
    const openWindows = visibleCourts.flatMap((c) => {
      const d = dayForCourt(schedules.data, c.id, anchor);
      return d ? windowsForDay(d) : [];
    });
    hours = computeGridHours(openWindows, shown, [anchor]);
    columns = visibleCourts.map((c) => {
      const d = dayForCourt(schedules.data, c.id, anchor);
      return {
        key: c.id,
        day: anchor,
        today: isSameDay(anchor, now),
        events: eventsOnDay(shown, anchor).filter((e) => e.courtId === c.id),
        open: d ? windowsForDay(d) : [],
        header: (
          <div className="text-center">
            <p className="text-sm font-semibold">{c.name}</p>
            <p className="text-[11px] capitalize text-muted-foreground">
              {c.type.toLowerCase()}
            </p>
          </div>
        ),
      };
    });
  } else if (view === "week") {
    const openWindows = days.flatMap((day) =>
      visibleCourts.flatMap((c) => {
        const d = dayForCourt(schedules.data, c.id, day);
        return d ? windowsForDay(d) : [];
      }),
    );
    hours = computeGridHours(openWindows, shown, days);
    columns = days.map((day) => {
      const today = isSameDay(day, now);
      return {
        key: String(day.getTime()),
        day,
        today,
        events: eventsOnDay(shown, day),
        header: (
          <button
            type="button"
            onClick={() => pickDay(day)}
            className="block w-full text-center leading-tight"
          >
            <span
              className={cn(
                "block text-sm font-semibold",
                today && "text-primary",
              )}
            >
              {day.toLocaleDateString("en-IN", { weekday: "short" })}
            </span>
            <span
              className={cn(
                "mt-0.5 block text-sm",
                today ? "font-semibold text-primary" : "text-muted-foreground",
              )}
            >
              {day.getDate()}{" "}
              {day.toLocaleDateString("en-IN", { month: "short" })}
            </span>
          </button>
        ),
      };
    });
  }

  const calendarBusy =
    calendar.isPlaceholderData || (calendar.isFetching && !calendar.data);
  const noCourts = sportCourts.length === 0;

  const courtView = (
    <div
      className={cn(
        "relative transition-opacity",
        calendar.isPlaceholderData && "opacity-60",
      )}
    >
      {noCourts ? (
        <p className="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">
          No courts configured for this sport.
        </p>
      ) : calendar.isError ? (
        <p className="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">
          Unable to load availability. Please try again.
        </p>
      ) : !calendar.data ? (
        <Skeleton className="h-[480px] w-full rounded-xl" />
      ) : view === "agenda" ? (
        <BookingAgenda
          events={shown}
          days={days}
          courtOrder={courtOrder}
          courtName={courtName}
          onEventClick={handleEventClick}
          now={now}
        />
      ) : view === "month" ? (
        <BookingMonthGrid
          anchor={anchor}
          events={shown}
          onPickDay={pickDay}
          courtOrder={courtOrder}
          courtName={courtName}
          now={now}
        />
      ) : columns.length === 0 ? (
        <p className="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">
          No courts to show.
        </p>
      ) : (
        <BookingTimeGrid
          columns={columns}
          startHour={hours.startHour}
          endHour={hours.endHour}
          now={now}
          onEventClick={handleEventClick}
          onEmptyClick={
            view === "day" ? handleEmptyClick : (col) => pickDay(col.day)
          }
          courtName={view === "week" ? courtName : undefined}
          courtOrder={courtOrder}
          maxLanes={view === "week" ? 2 : undefined}
          onOverflowClick={(col) => pickDay(col.day)}
        />
      )}
      {calendarBusy && calendar.data && (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
          <Loader2
            className="h-6 w-6 animate-spin text-primary"
            aria-label="Loading"
          />
        </div>
      )}
    </div>
  );

  return (
    <div className="space-y-4">
      {/* Tabs */}
      <div className="flex gap-6" role="tablist">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => setTab(t.key)}
            className={cn(
              "border-b-2 px-1 pb-2.5 pt-1 text-sm font-medium transition-colors",
              tab === t.key
                ? "border-primary text-primary"
                : "border-transparent text-muted-foreground hover:text-foreground",
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* Calendar only: navigation and view on top, then the legend that doubles as show/hide switches. */}
      {tab === "court" && (
        <>
          <BookingToolbar
            view={view}
            onViewChange={setView}
            anchor={anchor}
            onPrev={() => setAnchor((a) => shiftAnchor(view, a, -1))}
            onNext={() => setAnchor((a) => shiftAnchor(view, a, 1))}
            onToday={() => setAnchor(new Date())}
            onGuestBooking={() => router.push("/guest-bookings/new")}
          />
          <CalendarLegendBar
            hidden={hiddenKinds}
            onToggle={(kind, visible) =>
              setHiddenKinds((prev) => {
                const next = new Set(prev);
                if (visible) next.delete(kind);
                else next.add(kind);
                return next;
              })
            }
            courts={sportCourts.map((c) => ({ id: c.id, name: c.name }))}
            courtId={courtFilter}
            onCourtChange={setCourtFilter}
          />
        </>
      )}
      {/* List tabs: the filter row lands here, full width and outside the table card, like the calendar's. */}
      {tab !== "court" && <div ref={setToolbarSlot} />}

      <div className="grid gap-4">
        <div className="min-w-0 space-y-4">
          {tab === "court" ? (
            <>
              {courtView}
            </>
          ) : (
            facilityId && (
              <BookingListTab
                facilityId={facilityId}
                courts={sportCourts.map((c) => ({ id: c.id, name: c.name }))}
                courtName={courtName}
                onOpenBooking={(booking, mode = "view") => {
                  setDetailsMode(mode);
                  setDetailsBooking(booking);
                }}
                onChanged={reloadAll}
                schedules={schedules.data}
                activeMembers={facilityStats.data?.activeMembers}
                refreshKey={listRefresh}
                toolbarSlot={toolbarSlot}
              />
            )
          )}

          {/* Court View's cards; the list tabs draw their own from the list's range and filters. */}
          {tab === "court" && (
            <BookingStatsRow
              totalGuestBookings={stats.guestBookings}
              guestSub={PERIOD_NOUN[view]}
              guestDelta={stats.guestDelta}
              activeMembers={facilityStats.data?.activeMembers}
              utilizationPercent={stats.exactPercent}
              courtsActive={stats.activeCourts}
              courtsTotal={visibleCourts.length}
              utilizationDelta={stats.utilizationDelta}
              revenueInr={periodRevenue.data}
              revenueSub={`For the selected ${view === "agenda" ? "month" : view}`}
              revenueDelta={revenueDelta}
            />
          )}
        </div>
      </div>

      {facilityId && (
        <>
          <BookingDialog
            open={bookingDialog !== null}
            onOpenChange={(open) => !open && setBookingDialog(null)}
            facilityId={facilityId}
            date={bookingDialog?.date ?? anchor}
            facilitySports={facilitySports}
            sports={sports}
            areas={areas}
            initialCourtId={bookingDialog?.courtId}
            initialSlot={bookingDialog?.slot}
            onBooked={() => reloadAll()}
          />
          <BookingDetailsDialog
            open={detailsBooking !== null}
            onOpenChange={(open) => !open && setDetailsBooking(null)}
            booking={detailsBooking}
            initialMode={detailsMode}
            court={areas.find((a) => a.id === detailsBooking?.courtId)}
            sportName={
              sports.find(
                (s) =>
                  s.id ===
                  facilitySports.find(
                    (fs) => fs.id === detailsBooking?.facilitySportId,
                  )?.sportId,
              )?.name ?? "Sport"
            }
            facilityId={facilityId}
            onChanged={() => reloadAll()}
          />
          <Dialog
            open={membershipSlotDialog !== null}
            onOpenChange={(open) => !open && setMembershipSlotDialog(null)}
          >
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Membership Session</DialogTitle>
              </DialogHeader>
              {membershipSlotDialog && (
                <MembershipSlotCard
                  facilityId={facilityId}
                  slot={membershipSlotDialog}
                  onChanged={() => reloadAll()}
                />
              )}
            </DialogContent>
          </Dialog>
        </>
      )}
    </div>
  );
}
