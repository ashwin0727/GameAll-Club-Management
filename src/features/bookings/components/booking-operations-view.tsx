"use client";

import { useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getBookingService } from "@/services/bookings";
import { computeAvailableSlots } from "@/features/bookings/slots";
import { computeTodaysOperations } from "@/features/bookings/operations";
import type { Booking, TimeSlot } from "@/features/bookings/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { OperatingDay } from "@/features/operating-hours/types";
import { BookingDialog } from "@/features/bookings/components/booking-dialog";
import { BookingDetailsDialog } from "@/features/bookings/components/booking-details-dialog";

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}

function isToday(d: Date): boolean {
  const now = new Date();
  return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
}

export function BookingOperationsView() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");

  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);

  const [selectedDate, setSelectedDate] = useState(new Date());
  const [sportFilter, setSportFilter] = useState<string>("");
  const [dayByCourt, setDayByCourt] = useState<Map<string, OperatingDay | null>>(new Map());
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [gridLoading, setGridLoading] = useState(false);
  const [gridError, setGridError] = useState<string | null>(null);

  const [bookingDialog, setBookingDialog] = useState<{ courtId?: string; slot?: TimeSlot } | null>(null);
  const [detailsBooking, setDetailsBooking] = useState<Booking | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const facility = await getFacilityService().getFacility();
      if (cancelled) return;
      if (!facility) {
        setLoadState("none");
        return;
      }
      const [fs, allSports, playingAreas] = await Promise.all([
        getSportsService().getFacilitySports(facility.id),
        getSportsService().getActiveSports(),
        getPlayingAreasService().getPlayingAreas(facility.id),
      ]);
      if (cancelled) return;
      setFacilityId(facility.id);
      setFacilitySports(fs.filter((s) => s.enabled));
      setSports(allSports);
      setAreas(playingAreas.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
      setLoadState("ready");
    })().catch(() => setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  const reloadGrid = useMemo(
    () => async () => {
      if (!facilityId || areas.length === 0) return;
      setGridLoading(true);
      setGridError(null);
      try {
        const dayStart = new Date(selectedDate);
        dayStart.setHours(0, 0, 0, 0);
        const dayEnd = new Date(dayStart);
        dayEnd.setDate(dayEnd.getDate() + 1);
        const dow = dayStart.getDay();

        const [dayBookings, facilitySchedule] = await Promise.all([
          getBookingService().getBookingsForFacility(facilityId, dayStart, dayEnd),
          getOperatingHoursService().getFacilitySchedule(facilityId),
        ]);

        const overrides = await Promise.all(
          areas.map(async (a) => [a.id, await getOperatingHoursService().getPlayingAreaSchedule(a.id)] as const),
        );
        const nextDayByCourt = new Map<string, OperatingDay | null>();
        for (const [courtId, override] of overrides) {
          const schedule = override ?? facilitySchedule;
          nextDayByCourt.set(courtId, schedule?.days.find((d) => d.dayOfWeek === dow) ?? null);
        }

        setBookings(dayBookings);
        setDayByCourt(nextDayByCourt);
      } catch {
        setGridError("Unable to load availability. Please try again.");
      } finally {
        setGridLoading(false);
      }
    },
    [facilityId, areas, selectedDate],
  );

  useEffect(() => {
    reloadGrid();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [facilityId, areas.length, selectedDate]);

  const bookingsByCourt = useMemo(() => {
    const map = new Map<string, Booking[]>();
    for (const b of bookings) {
      if (b.status !== "pending" && b.status !== "confirmed") continue;
      const list = map.get(b.courtId) ?? [];
      list.push(b);
      map.set(b.courtId, list);
    }
    return map;
  }, [bookings]);

  const slotsByCourt = useMemo(() => {
    const map = new Map<string, TimeSlot[]>();
    for (const area of areas) {
      const day = dayByCourt.get(area.id);
      map.set(area.id, day ? computeAvailableSlots(selectedDate, day, bookingsByCourt.get(area.id) ?? []) : []);
    }
    return map;
  }, [areas, dayByCourt, bookingsByCourt, selectedDate]);

  const operations = useMemo(() => computeTodaysOperations(bookings, new Date()), [bookings]);

  const groupedSports = useMemo(() => {
    const filtered = sportFilter ? facilitySports.filter((fs) => fs.id === sportFilter) : facilitySports;
    return filtered
      .map((fs) => ({ facilitySport: fs, courts: areas.filter((a) => a.facilitySportId === fs.id) }))
      .filter((g) => g.courts.length > 0);
  }, [facilitySports, areas, sportFilter]);

  function findBookingAt(courtId: string, startTimeIso: string): Booking | undefined {
    return (bookingsByCourt.get(courtId) ?? []).find((b) => b.startTime === startTimeIso);
  }

  function handleCellClick(courtId: string, slot: TimeSlot) {
    if (slot.available) {
      setBookingDialog({ courtId, slot });
      return;
    }
    const booking = findBookingAt(courtId, slot.startTime);
    if (booking) setDetailsBooking(booking);
  }

  if (loadState === "loading") {
    return (
      <div className="space-y-4">
        <Skeleton className="h-11 w-full rounded-md" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }
  if (loadState === "none") {
    return <p className="text-sm text-muted-foreground">Complete your facility setup before taking bookings.</p>;
  }
  if (loadState === "error") {
    return <p className="text-sm text-muted-foreground">Unable to load bookings. Please try again.</p>;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2">
          <Button type="button" variant="outline" size="sm" onClick={() => setSelectedDate((d) => new Date(d.getTime() - 86400000))}>
            ←
          </Button>
          <div className="text-sm font-medium">
            {isToday(selectedDate) ? "Today — " : ""}
            {selectedDate.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}
          </div>
          <Button type="button" variant="outline" size="sm" onClick={() => setSelectedDate((d) => new Date(d.getTime() + 86400000))}>
            →
          </Button>
          {!isToday(selectedDate) && (
            <Button type="button" variant="ghost" size="sm" onClick={() => setSelectedDate(new Date())}>
              Today
            </Button>
          )}
        </div>
        <Button type="button" onClick={() => setBookingDialog({})}>
          + Create Booking
        </Button>
      </div>

      {/* Today's Operations */}
      {isToday(selectedDate) && (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <div className="rounded-lg border border-border bg-card p-3">
            <p className="text-xs text-muted-foreground">Today&apos;s Bookings</p>
            <p className="text-lg font-semibold">{operations.totalBookings}</p>
          </div>
          <div className="rounded-lg border border-border bg-card p-3">
            <p className="text-xs text-muted-foreground">Upcoming</p>
            <p className="text-lg font-semibold">{operations.upcoming}</p>
          </div>
          <div className="rounded-lg border border-border bg-card p-3">
            <p className="text-xs text-muted-foreground">Currently Occupied</p>
            <p className="text-lg font-semibold">{operations.currentlyOccupied}</p>
          </div>
        </div>
      )}

      {/* Filters */}
      <select
        aria-label="Sport filter"
        value={sportFilter}
        onChange={(e) => setSportFilter(e.target.value)}
        className="h-11 min-w-[10rem] rounded-md border border-input bg-secondary/60 px-3 text-sm"
      >
        <option value="">All Sports</option>
        {facilitySports.map((fs) => {
          const s = sports.find((sp) => sp.id === fs.sportId);
          return (
            <option key={fs.id} value={fs.id}>
              {fs.customSportName ?? s?.name ?? "Sport"}
            </option>
          );
        })}
      </select>

      {/* Availability */}
      {gridLoading ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : gridError ? (
        <p className="text-sm text-muted-foreground">{gridError}</p>
      ) : groupedSports.length === 0 ? (
        <p className="text-sm text-muted-foreground">No courts configured for this sport.</p>
      ) : (
        <div className="space-y-6">
          {groupedSports.map(({ facilitySport, courts }) => {
            const sport = sports.find((s) => s.id === facilitySport.sportId);
            return (
              <div key={facilitySport.id} className="space-y-2">
                <h3 className="text-sm font-semibold">{facilitySport.customSportName ?? sport?.name ?? "Sport"}</h3>
                <div className="space-y-3">
                  {courts.map((court) => {
                    const slots = slotsByCourt.get(court.id) ?? [];
                    return (
                      <div key={court.id} className="rounded-lg border border-border bg-card p-3">
                        <p className="mb-2 text-sm font-medium">{court.name}</p>
                        {slots.length === 0 ? (
                          <p className="text-xs text-muted-foreground">Closed on this date.</p>
                        ) : (
                          <div className="flex flex-wrap gap-1.5">
                            {slots.map((slot) => (
                              <button
                                key={slot.startTime}
                                type="button"
                                onClick={() => handleCellClick(court.id, slot)}
                                title={formatTime(slot.startTime)}
                                className={`h-9 rounded-md border px-2 text-[11px] font-medium transition-colors ${
                                  slot.available
                                    ? "border-success/40 bg-success/10 text-success hover:bg-success/20"
                                    : "border-input bg-muted text-muted-foreground hover:bg-accent"
                                }`}
                              >
                                {formatTime(slot.startTime)}
                              </button>
                            ))}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {facilityId && (
        <>
          <BookingDialog
            open={bookingDialog !== null}
            onOpenChange={(open) => !open && setBookingDialog(null)}
            facilityId={facilityId}
            date={selectedDate}
            facilitySports={facilitySports}
            sports={sports}
            areas={areas}
            initialCourtId={bookingDialog?.courtId}
            initialSlot={bookingDialog?.slot}
            onBooked={() => reloadGrid()}
          />
          <BookingDetailsDialog
            open={detailsBooking !== null}
            onOpenChange={(open) => !open && setDetailsBooking(null)}
            booking={detailsBooking}
            court={areas.find((a) => a.id === detailsBooking?.courtId)}
            sportName={
              sports.find((s) => s.id === facilitySports.find((fs) => fs.id === detailsBooking?.facilitySportId)?.sportId)?.name ?? "Sport"
            }
            facilityId={facilityId}
            onChanged={() => reloadGrid()}
          />
        </>
      )}
    </div>
  );
}