"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Check, ChevronRight, Clock, MapPin, CalendarDays, Trophy, Info, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getBookingService } from "@/services/bookings";
import { getPricingService } from "@/services/pricing";
import { computeAvailableSlots } from "@/features/bookings/slots";
import { formatCurrency } from "@/features/pricing/money";
import { ServiceError } from "@/services/shared/service-error";
import type { Booking, TimeSlot } from "@/features/bookings/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { Facility } from "@/features/onboarding/types";

const STEPS = ["Select Court & Time", "Guest Details", "Review & Confirm", "Payment (Offline)"] as const;

function hhmm(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}
function localHHMM(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}
function fmtDateLong(d: Date): string {
  return d.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric", weekday: "short" });
}
function toDateInput(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

const selectCls =
  "h-11 w-full appearance-none rounded-lg border border-input bg-background px-3 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30";

export function GuestBookingWizard() {
  const router = useRouter();

  const [facility, setFacility] = useState<Facility | null>(null);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);
  const [loading, setLoading] = useState(true);

  const [step, setStep] = useState(0);
  const [facilitySportId, setFacilitySportId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [date, setDate] = useState(() => new Date());
  const [slot, setSlot] = useState<TimeSlot | null>(null);
  const [slots, setSlots] = useState<TimeSlot[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);

  const [guestName, setGuestName] = useState("");
  const [guestPhone, setGuestPhone] = useState("");
  const [guestEmail, setGuestEmail] = useState("");
  const [notes, setNotes] = useState("");

  const [priceMinor, setPriceMinor] = useState<number | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [booked, setBooked] = useState<Booking | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const f = await getFacilityService().getFacility();
      if (cancelled || !f) {
        setLoading(false);
        return;
      }
      const [fs, allSports, pa] = await Promise.all([
        getSportsService().getFacilitySports(f.id),
        getSportsService().getActiveSports(),
        getPlayingAreasService().getPlayingAreas(f.id),
      ]);
      if (cancelled) return;
      setFacility(f);
      const enabledSports = fs.filter((s) => s.enabled);
      setFacilitySports(enabledSports);
      setSports(allSports);
      setAreas(pa.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
      setFacilitySportId(enabledSports[0]?.id ?? "");
      setLoading(false);
    })().catch(() => setLoading(false));
    return () => {
      cancelled = true;
    };
  }, []);

  const courtsForSport = useMemo(() => areas.filter((a) => a.facilitySportId === facilitySportId), [areas, facilitySportId]);
  const court = areas.find((a) => a.id === courtId) ?? null;
  const sportName = useMemo(() => {
    const fs = facilitySports.find((x) => x.id === facilitySportId);
    return fs?.customSportName ?? sports.find((s) => s.id === fs?.sportId)?.name ?? "";
  }, [facilitySports, sports, facilitySportId]);

  // Load slots for the picked court + date.
  useEffect(() => {
    if (!facility || !courtId) {
      setSlots([]);
      return;
    }
    let cancelled = false;
    setSlotsLoading(true);
    (async () => {
      const dow = date.getDay();
      const [override, facilitySchedule, existing] = await Promise.all([
        getOperatingHoursService().getPlayingAreaSchedule(courtId),
        getOperatingHoursService().getFacilitySchedule(facility.id),
        getBookingService().getBookingsForCourtOnDate(courtId, date),
      ]);
      if (cancelled) return;
      const schedule = override ?? facilitySchedule;
      const day = schedule?.days.find((d) => d.dayOfWeek === dow) ?? null;
      setSlots(day ? computeAvailableSlots(date, day, existing) : []);
      setSlotsLoading(false);
    })().catch(() => {
      if (!cancelled) {
        setSlots([]);
        setSlotsLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [facility, courtId, date]);

  // Resolve the hourly price for the chosen slot.
  useEffect(() => {
    if (!facility || !facilitySportId || !slot) {
      setPriceMinor(null);
      return;
    }
    let cancelled = false;
    getPricingService()
      .resolvePrice(facility.id, facilitySportId, courtId || null, date, localHHMM(slot.startTime))
      .then((rule) => !cancelled && setPriceMinor(rule?.amountMinor ?? null))
      .catch(() => !cancelled && setPriceMinor(null));
    return () => {
      cancelled = true;
    };
  }, [facility, facilitySportId, courtId, date, slot]);

  const currency = "INR";
  const durationMs = slot ? new Date(slot.endTime).getTime() - new Date(slot.startTime).getTime() : 0;
  const hours = durationMs / 3_600_000;
  const totalMinor = priceMinor == null ? null : Math.round(priceMinor * hours);

  const canNext = useCallback(() => {
    if (step === 0) return !!courtId && !!slot;
    if (step === 1) return guestName.trim().length >= 2 && guestPhone.trim().length >= 6;
    return true;
  }, [step, courtId, slot, guestName, guestPhone]);

  async function confirm() {
    if (!facility || !courtId || !slot) return;
    setSubmitting(true);
    setError(null);
    try {
      const extra = guestEmail.trim() ? `Email: ${guestEmail.trim()}` : "";
      const finalNotes = [notes.trim(), extra].filter(Boolean).join(" · ") || null;
      const b = await getBookingService().createBooking({
        facilityId: facility.id,
        courtId,
        startTime: slot.startTime,
        endTime: slot.endTime,
        customerType: "GUEST",
        guestName: guestName.trim(),
        guestPhone: guestPhone.trim() || null,
        notes: finalNotes,
        paymentStatus: "PENDING",
      });
      setBooked(b);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to create this booking.");
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) return <Skeleton className="h-[600px] w-full rounded-xl" />;
  if (!facility) return <p className="text-sm text-muted-foreground">Complete your facility setup first.</p>;

  if (booked) {
    return (
      <div className="mx-auto max-w-lg space-y-4 py-10 text-center">
        <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-success/15 text-success">
          <Check className="h-6 w-6" />
        </span>
        <h1 className="text-xl font-semibold">Booking confirmed</h1>
        <p className="text-sm text-muted-foreground">
          {sportName} · {court?.name} · {fmtDateLong(date)} · {hhmm(booked.startTime)} – {hhmm(booked.endTime)}
        </p>
        <p className="text-sm text-muted-foreground">Payment is to be collected offline at the venue.</p>
        <div className="flex justify-center gap-2">
          <Button type="button" variant="outline" onClick={() => router.push("/bookings")}>
            Back to Bookings
          </Button>
          <Button
            type="button"
            onClick={() => {
              setBooked(null);
              setStep(0);
              setSlot(null);
              setGuestName("");
              setGuestPhone("");
              setGuestEmail("");
              setNotes("");
            }}
          >
            New Booking
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <button
          type="button"
          onClick={() => router.push("/bookings")}
          className="mb-1 inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> Bookings
        </button>
        <h1 className="text-2xl font-semibold">Guest Booking</h1>
        <p className="text-sm text-muted-foreground">Book your favorite court in a few simple steps</p>
      </div>

      {/* Steps */}
      <div className="flex flex-wrap items-center gap-x-2 gap-y-3">
        {STEPS.map((label, i) => (
          <div key={label} className="flex items-center gap-2">
            <span
              className={cn(
                "flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold",
                i < step ? "bg-success text-white" : i === step ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground",
              )}
            >
              {i < step ? <Check className="h-3.5 w-3.5" /> : i + 1}
            </span>
            <span className={cn("text-sm", i === step ? "font-medium text-foreground" : "text-muted-foreground")}>{label}</span>
            {i < STEPS.length - 1 && <span className="mx-1 hidden h-px w-8 bg-border sm:block" />}
          </div>
        ))}
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        {/* Main panel */}
        <div className="rounded-xl border border-border p-5">
          {step === 0 && (
            <div className="space-y-5">
              <div className="grid gap-3 sm:grid-cols-3">
                <label className="space-y-1">
                  <span className="flex items-center gap-1.5 text-xs text-muted-foreground"><Trophy className="h-3.5 w-3.5" /> Sport</span>
                  <select
                    value={facilitySportId}
                    onChange={(e) => {
                      setFacilitySportId(e.target.value);
                      setCourtId("");
                      setSlot(null);
                    }}
                    className={selectCls}
                  >
                    {facilitySports.map((fs) => {
                      const s = sports.find((sp) => sp.id === fs.sportId);
                      return (
                        <option key={fs.id} value={fs.id}>
                          {fs.customSportName ?? s?.name ?? "Sport"}
                        </option>
                      );
                    })}
                  </select>
                </label>
                <label className="space-y-1">
                  <span className="flex items-center gap-1.5 text-xs text-muted-foreground"><MapPin className="h-3.5 w-3.5" /> Location</span>
                  <select value={facility.id} disabled className={cn(selectCls, "opacity-70")}>
                    <option value={facility.id}>{facility.name}</option>
                  </select>
                </label>
                <label className="space-y-1">
                  <span className="flex items-center gap-1.5 text-xs text-muted-foreground"><CalendarDays className="h-3.5 w-3.5" /> Date</span>
                  <input
                    type="date"
                    value={toDateInput(date)}
                    min={toDateInput(new Date())}
                    onChange={(e) => {
                      const [y, m, d] = e.target.value.split("-").map(Number);
                      if (y && m && d) {
                        setDate(new Date(y, m - 1, d));
                        setSlot(null);
                      }
                    }}
                    className={selectCls}
                  />
                </label>
              </div>

              <div>
                <p className="mb-2 text-sm font-semibold">Select Court</p>
                {courtsForSport.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No bookable courts for this sport.</p>
                ) : (
                  <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                    {courtsForSport.map((c) => {
                      const active = courtId === c.id;
                      return (
                        <button
                          key={c.id}
                          type="button"
                          onClick={() => {
                            setCourtId(c.id);
                            setSlot(null);
                          }}
                          className={cn(
                            "relative overflow-hidden rounded-lg border p-0 text-left transition",
                            active ? "border-primary ring-2 ring-primary/30" : "border-border hover:border-primary/50",
                          )}
                        >
                          <div className="flex h-20 items-center justify-center bg-gradient-to-br from-emerald-900 to-emerald-700 text-[10px] text-emerald-200">
                            COURT
                          </div>
                          {active && (
                            <span className="absolute right-1.5 top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-primary text-primary-foreground">
                              <Check className="h-3 w-3" />
                            </span>
                          )}
                          <div className="p-2">
                            <p className="text-sm font-medium">{c.name}</p>
                            <p className="text-xs text-muted-foreground">{c.type === "INDOOR" ? "Indoor" : "Outdoor"}</p>
                          </div>
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>

              {courtId && (
                <div>
                  <p className="mb-2 text-sm font-semibold">Select Time Slot</p>
                  {slotsLoading ? (
                    <p className="text-sm text-muted-foreground">Loading availability…</p>
                  ) : slots.length === 0 ? (
                    <p className="text-sm text-muted-foreground">No slots available on this date.</p>
                  ) : (
                    <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                      {slots.map((s) => {
                        const active = slot?.startTime === s.startTime;
                        return (
                          <button
                            key={s.startTime}
                            type="button"
                            disabled={!s.available}
                            onClick={() => setSlot(s)}
                            className={cn(
                              "rounded-lg border px-3 py-2 text-center transition",
                              active
                                ? "border-primary bg-primary/10"
                                : s.available
                                  ? "border-border hover:border-primary/50"
                                  : "cursor-not-allowed border-border bg-muted opacity-60",
                            )}
                          >
                            <p className="text-sm font-medium">{hhmm(s.startTime)}</p>
                            <p className={cn("text-[11px]", active ? "text-primary" : s.available ? "text-success" : "text-muted-foreground line-through")}>
                              {s.available ? "Available" : "Booked"}
                            </p>
                          </button>
                        );
                      })}
                    </div>
                  )}
                </div>
              )}

              {slot && (
                <div className="flex items-center gap-2 rounded-lg bg-success/10 px-3 py-2 text-sm text-foreground">
                  <Clock className="h-4 w-4 text-success" />
                  Selected Time: <span className="font-medium">{fmtDateLong(date)}</span> ·{" "}
                  <span className="font-medium text-success">
                    {hhmm(slot.startTime)} – {hhmm(slot.endTime)} ({hours} Hour{hours === 1 ? "" : "s"})
                  </span>
                </div>
              )}
            </div>
          )}

          {step === 1 && (
            <div className="max-w-md space-y-4">
              <p className="text-sm font-semibold">Guest Details</p>
              <label className="block space-y-1">
                <span className="text-xs text-muted-foreground">Full Name *</span>
                <Input value={guestName} onChange={(e) => setGuestName(e.target.value)} placeholder="Guest name" />
              </label>
              <label className="block space-y-1">
                <span className="text-xs text-muted-foreground">Phone Number *</span>
                <Input value={guestPhone} onChange={(e) => setGuestPhone(e.target.value)} placeholder="Phone number" inputMode="tel" />
              </label>
              <label className="block space-y-1">
                <span className="text-xs text-muted-foreground">Email (optional)</span>
                <Input value={guestEmail} onChange={(e) => setGuestEmail(e.target.value)} placeholder="Email address" type="email" />
              </label>
              <label className="block space-y-1">
                <span className="text-xs text-muted-foreground">Notes (optional)</span>
                <Input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Anything the venue should know" />
              </label>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-4">
              <p className="text-sm font-semibold">Review &amp; Confirm</p>
              <dl className="divide-y divide-border/60 text-sm">
                <Row label="Guest" value={`${guestName}${guestPhone ? ` · ${guestPhone}` : ""}`} />
                {guestEmail && <Row label="Email" value={guestEmail} />}
                <Row label="Sport" value={sportName} />
                <Row label="Location" value={facility.name} />
                <Row label="Court" value={court?.name ?? "—"} />
                <Row label="Date" value={fmtDateLong(date)} />
                <Row label="Time" value={slot ? `${hhmm(slot.startTime)} – ${hhmm(slot.endTime)}` : "—"} />
                <Row label="Duration" value={`${hours} Hour${hours === 1 ? "" : "s"}`} />
                {notes && <Row label="Notes" value={notes} />}
                <Row label="Total" value={totalMinor == null ? "—" : formatCurrency(totalMinor, currency)} />
              </dl>
            </div>
          )}

          {step === 3 && (
            <div className="space-y-4">
              <p className="text-sm font-semibold">Payment (Offline)</p>
              <div className="flex items-start gap-2 rounded-lg border border-border bg-secondary/40 p-3 text-sm">
                <Info className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                <div>
                  <p className="font-medium">Payment is to be made offline</p>
                  <p className="text-muted-foreground">
                    Collect {totalMinor == null ? "the amount" : formatCurrency(totalMinor, currency)} at the venue. The booking is created
                    with payment status <span className="font-medium">Pending</span>.
                  </p>
                </div>
              </div>
              {error && <p className="text-sm text-destructive">{error}</p>}
            </div>
          )}
        </div>

        {/* Summary sidebar */}
        <aside className="h-fit rounded-xl border border-border p-4">
          <p className="text-sm font-semibold">Booking Summary</p>
          <div className="mt-3 flex h-28 items-center justify-center rounded-lg bg-gradient-to-br from-emerald-900 to-emerald-700 text-xs text-emerald-200">
            {court?.name ?? "Select a court"}
          </div>
          <dl className="mt-4 space-y-2.5 text-sm">
            <SummaryRow icon={Trophy} label="Sport" value={sportName || "—"} />
            <SummaryRow icon={MapPin} label="Location" value={facility.name} />
            <SummaryRow icon={MapPin} label="Court" value={court?.name ?? "—"} />
            <SummaryRow icon={CalendarDays} label="Date" value={fmtDateLong(date)} />
            <SummaryRow icon={Clock} label="Time" value={slot ? `${hhmm(slot.startTime)} – ${hhmm(slot.endTime)}` : "—"} />
            <SummaryRow icon={Clock} label="Duration" value={slot ? `${hours} Hour${hours === 1 ? "" : "s"}` : "—"} />
          </dl>
          <div className="mt-4 border-t border-border pt-3">
            <p className="text-sm font-semibold">Price Details</p>
            <div className="mt-2 flex justify-between text-sm text-muted-foreground">
              <span>Court Price (Per Hour)</span>
              <span>{priceMinor == null ? "—" : formatCurrency(priceMinor, currency)}</span>
            </div>
            <div className="mt-1 flex justify-between text-sm font-semibold text-success">
              <span>Total Amount</span>
              <span>{totalMinor == null ? "—" : formatCurrency(totalMinor, currency)}</span>
            </div>
          </div>
          <div className="mt-3 flex items-start gap-2 rounded-lg bg-secondary/40 p-2.5 text-xs">
            <Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" />
            <div>
              <p className="font-medium">Payment is to be made offline</p>
              <p className="text-muted-foreground">You will pay at the venue</p>
            </div>
          </div>
        </aside>
      </div>

      {/* Footer nav */}
      <div className="flex items-center justify-between">
        {step === 0 ? (
          <Button type="button" variant="outline" onClick={() => router.push("/bookings")}>
            Cancel
          </Button>
        ) : (
          <Button type="button" variant="outline" onClick={() => setStep((s) => s - 1)}>
            Back
          </Button>
        )}
        {step < 3 ? (
          <Button type="button" onClick={() => setStep((s) => s + 1)} disabled={!canNext()}>
            Next: {STEPS[step + 1]} <ChevronRight className="ml-1 h-4 w-4" />
          </Button>
        ) : (
          <Button type="button" onClick={confirm} disabled={submitting}>
            {submitting ? "Confirming…" : "Confirm Booking"}
          </Button>
        )}
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4 py-2">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-right font-medium text-foreground">{value}</dd>
    </div>
  );
}

function SummaryRow({ icon: Icon, label, value }: { icon: React.ComponentType<{ className?: string }>; label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="flex items-center gap-1.5 text-muted-foreground">
        <Icon className="h-3.5 w-3.5" /> {label}
      </span>
      <span className="truncate text-right font-medium text-foreground">{value}</span>
    </div>
  );
}