"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getBookingService } from "@/services/bookings";
import { computeAvailableSlots } from "@/features/bookings/slots";
import { ServiceError } from "@/services/shared/service-error";
import type { Booking, TimeSlot } from "@/features/bookings/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";

const selectCls = "h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm";

function hhmm(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}
function dateInput(iso: string): string {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function GuestBookingEditPage({ bookingId }: { bookingId: string }) {
  const router = useRouter();
  const [booking, setBooking] = useState<Booking | null>(null);
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [areas, setAreas] = useState<PlayingArea[]>([]);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  const [guestName, setGuestName] = useState("");
  const [guestPhone, setGuestPhone] = useState("");
  const [players, setPlayers] = useState("1");
  const [notes, setNotes] = useState("");

  const [courtId, setCourtId] = useState("");
  const [date, setDate] = useState("");
  const [slot, setSlot] = useState<TimeSlot | null>(null);
  const [slots, setSlots] = useState<TimeSlot[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const [b, f] = await Promise.all([getBookingService().getBooking(bookingId), getFacilityService().getFacility()]);
        if (!b || b.customerType !== "GUEST" || !f) {
          setNotFound(true);
          setLoading(false);
          return;
        }
        const [fs, allSports, pa] = await Promise.all([
          getSportsService().getFacilitySports(f.id),
          getSportsService().getActiveSports(),
          getPlayingAreasService().getPlayingAreas(f.id),
        ]);
        setBooking(b);
        setFacilityId(f.id);
        setFacilitySports(fs.filter((x) => x.enabled));
        setSports(allSports);
        setAreas(pa.filter((a) => !a.archived));
        setGuestName(b.guestName ?? "");
        setGuestPhone(b.guestPhone ?? "");
        setPlayers(String(b.partySize || 1));
        setNotes(b.notes ?? "");
        setCourtId(b.courtId);
        setDate(dateInput(b.startTime));
        setLoading(false);
      } catch {
        setNotFound(true);
        setLoading(false);
      }
    })();
  }, [bookingId]);

  const court = areas.find((a) => a.id === courtId) ?? null;
  const sportName = useMemo(() => {
    const fs = facilitySports.find((x) => x.id === court?.facilitySportId);
    return fs?.customSportName ?? sports.find((s) => s.id === fs?.sportId)?.name ?? "";
  }, [facilitySports, sports, court]);

  const courtsForSport = useMemo(
    () => (court ? areas.filter((a) => a.facilitySportId === court.facilitySportId) : areas),
    [areas, court],
  );

  const timeChanged = useMemo(() => {
    if (!booking) return false;
    if (courtId !== booking.courtId) return true;
    if (dateInput(booking.startTime) !== date) return true;
    return slot != null && slot.startTime !== booking.startTime;
  }, [booking, courtId, date, slot]);

  const loadSlots = useCallback(async () => {
    if (!facilityId || !courtId || !date) return;
    setSlotsLoading(true);
    const d = new Date(`${date}T00:00:00`);
    const [override, facilitySchedule, existing] = await Promise.all([
      getOperatingHoursService().getPlayingAreaSchedule(courtId),
      getOperatingHoursService().getFacilitySchedule(facilityId),
      getBookingService().getBookingsForCourtOnDate(courtId, d),
    ]);
    const schedule = override ?? facilitySchedule;
    const day = schedule?.days.find((x) => x.dayOfWeek === d.getDay()) ?? null;
    setSlots(day ? computeAvailableSlots(d, day, existing.filter((x) => x.id !== bookingId)) : []);
    setSlotsLoading(false);
  }, [facilityId, courtId, date, bookingId]);

  useEffect(() => {
    if (timeChanged) void loadSlots();
    else setSlots([]);
  }, [timeChanged, loadSlots]);

  async function save() {
    if (!booking) return;
    if (guestName.trim().length < 2) return setError("Enter a guest name.");
    if (timeChanged && !slot) return setError("Pick a new time slot.");
    setSaving(true);
    setError(null);
    try {
      await getBookingService().updateGuestBooking(bookingId, {
        guestName: guestName.trim(),
        guestPhone: guestPhone.trim() || null,
        partySize: Math.max(1, Number(players) || 1),
        notes: notes.trim() || null,
      });
      if (timeChanged && slot) {
        await getBookingService().rescheduleBooking({ bookingId, courtId, startTime: slot.startTime, endTime: slot.endTime });
      }
      router.push("/guest-bookings");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to save this booking.");
      setSaving(false);
    }
  }

  if (loading) return <Skeleton className="h-[500px] w-full rounded-xl" />;
  if (notFound || !booking) {
    return (
      <div className="space-y-4">
        <button type="button" onClick={() => router.push("/guest-bookings")} className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="h-4 w-4" /> Guest Bookings
        </button>
        <Card className="p-10 text-center text-sm text-muted-foreground">This booking could not be found.</Card>
      </div>
    );
  }

  return (
    <div className="w-full space-y-5">
      <div>
        <button type="button" onClick={() => router.push("/guest-bookings")} className="mb-1 inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="h-4 w-4" /> Guest Bookings
        </button>
        <h1 className="text-xl font-semibold">Edit Guest Booking</h1>
        <p className="text-sm text-muted-foreground">Modify booking details</p>
      </div>

      <Card className="space-y-4 p-5">
        <p className="text-sm font-semibold">Guest</p>
        <div className="grid gap-4 sm:grid-cols-3">
          <label className="space-y-1.5 text-xs text-muted-foreground">
            Full name
            <Input value={guestName} onChange={(e) => setGuestName(e.target.value)} />
          </label>
          <label className="space-y-1.5 text-xs text-muted-foreground">
            Phone
            <Input value={guestPhone} onChange={(e) => setGuestPhone(e.target.value)} inputMode="tel" />
          </label>
          <label className="space-y-1.5 text-xs text-muted-foreground">
            Players
            <Input value={players} onChange={(e) => setPlayers(e.target.value)} inputMode="numeric" />
          </label>
        </div>
        <label className="block space-y-1.5 text-xs text-muted-foreground">
          Notes
          <Input value={notes} onChange={(e) => setNotes(e.target.value)} />
        </label>
      </Card>

      <Card className="space-y-4 p-5">
        <p className="text-sm font-semibold">Court &amp; time</p>
        <p className="text-xs text-muted-foreground">
          Currently {sportName} · {court?.name} · {new Date(booking.startTime).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })} · {hhmm(booking.startTime)} – {hhmm(booking.endTime)}
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="space-y-1.5 text-xs text-muted-foreground">
            Court
            <select
              value={courtId}
              onChange={(e) => {
                setCourtId(e.target.value);
                setSlot(null);
              }}
              className={selectCls}
            >
              {courtsForSport.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </label>
          <label className="space-y-1.5 text-xs text-muted-foreground">
            Date
            <input
              type="date"
              value={date}
              min={dateInput(new Date().toISOString())}
              onChange={(e) => {
                setDate(e.target.value);
                setSlot(null);
              }}
              className={selectCls}
            />
          </label>
        </div>
        {timeChanged && (
          <div>
            <p className="mb-2 text-xs text-muted-foreground">Pick a new slot</p>
            {slotsLoading ? (
              <p className="text-sm text-muted-foreground">Loading availability…</p>
            ) : slots.length === 0 ? (
              <p className="text-sm text-muted-foreground">No slots available on this date.</p>
            ) : (
              <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">
                {slots.map((s) => (
                  <button
                    key={s.startTime}
                    type="button"
                    disabled={!s.available}
                    onClick={() => setSlot(s)}
                    className={cn(
                      "rounded-md border px-2 py-1.5 text-xs",
                      slot?.startTime === s.startTime ? "border-primary bg-primary/10" : s.available ? "border-input hover:bg-accent" : "cursor-not-allowed border-input bg-muted opacity-60",
                    )}
                  >
                    {hhmm(s.startTime)}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </Card>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex items-center justify-between">
        <Button type="button" variant="outline" onClick={() => router.push("/guest-bookings")}>
          Cancel
        </Button>
        <Button type="button" onClick={save} disabled={saving}>
          {saving ? "Saving…" : "Save Changes"}
        </Button>
      </div>
    </div>
  );
}
