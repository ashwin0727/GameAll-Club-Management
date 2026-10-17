"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Check, ChevronRight, Clock, MapPin, CalendarDays, Trophy, Info, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getBookingService } from "@/services/bookings";
import { getPricingService } from "@/services/pricing";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { computeAvailableSlots } from "@/features/bookings/slots";
import { hoursBetween, mergeRuns, toggleSlot } from "@/features/bookings/slot-selection";
import { formatCurrency } from "@/features/pricing/money";
import { BookingPaymentLinkPanel } from "@/features/payments/components/booking-payment-link-panel";
import { SelectField } from "@/components/shared/select-field";
import { ServiceError } from "@/services/shared/service-error";
import type { Booking, TimeSlot } from "@/features/bookings/types";
import type { MembershipSessionSlot } from "@/features/membership-sessions/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";

const STEPS = ["Select Court & Time", "Guest Details", "Review & Confirm", "Payment"] as const;

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

/** A slot whose local start falls inside a membership batch's protected window is not bookable ad-hoc. */
function isMembershipBlocked(s: TimeSlot, membershipSlots: MembershipSessionSlot[]): boolean {
  const start = new Date(s.startTime);
  const minuteOfDay = start.getHours() * 60 + start.getMinutes();
  return membershipSlots.some((m) => {
    const [sh, sm] = m.startTime.split(":").map(Number);
    const [eh, em] = m.endTime.split(":").map(Number);
    return minuteOfDay >= (sh ?? 0) * 60 + (sm ?? 0) && minuteOfDay < (eh ?? 0) * 60 + (em ?? 0);
  });
}

const selectCls =
  "h-11 w-full appearance-none rounded-lg border border-input bg-background px-3 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30";
// SelectField draws its own list (rounded, themed) instead of the browser's square blue one.
const selectFieldCls = "h-11 rounded-lg border border-input bg-background px-3 text-sm focus-visible:ring-2 focus-visible:ring-primary/30";

export function GuestBookingWizard() {
  const router = useRouter();

  const { data: facility, isLoading: facilityLoading } = useFacility();
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);
  const [loading, setLoading] = useState(true);

  const [step, setStep] = useState(0);
  const [facilitySportId, setFacilitySportId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [date, setDate] = useState(() => new Date());
  // Any number of slots can be picked; touching ones become one booking (see mergeRuns).
  const [selected, setSelected] = useState<TimeSlot[]>([]);
  const [slots, setSlots] = useState<TimeSlot[]>([]);
  const [membershipSlots, setMembershipSlots] = useState<MembershipSessionSlot[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);

  const [guestName, setGuestName] = useState("");
  const [guestPhone, setGuestPhone] = useState("");
  const [guestEmail, setGuestEmail] = useState("");
  const [players, setPlayers] = useState("2");
  const [payMode, setPayMode] = useState<"offline" | "online">("offline");
  const [paymentMethod, setPaymentMethod] = useState("Cash");
  const [notes, setNotes] = useState("");

  // Hourly price resolved per selected slot (it can differ by time of day), keyed by the slot's start.
  const [priceByStart, setPriceByStart] = useState<Record<string, number | null>>({});
  const [bookedRuns, setBookedRuns] = useState<{ startTime: string; endTime: string }[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [booked, setBooked] = useState<Booking | null>(null);
  // "Pay Online": the booking exists and a payment link is being shared with the player, who pays on their own phone.
  const [linkBooking, setLinkBooking] = useState<Booking | null>(null);

  useEffect(() => {
    if (facilityLoading) return;
    if (!facility) {
      setLoading(false);
      return;
    }
    let cancelled = false;
    (async () => {
      const [fs, allSports, pa] = await Promise.all([
        getSportsService().getFacilitySports(facility.id),
        getSportsService().getActiveSports(),
        getPlayingAreasService().getPlayingAreas(facility.id),
      ]);
      if (cancelled) return;
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
  }, [facility, facilityLoading]);

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
    const dateStr = toDateInput(date);
    (async () => {
      const dow = date.getDay();
      const [override, facilitySchedule, existing, mSlots] = await Promise.all([
        getOperatingHoursService().getPlayingAreaSchedule(courtId),
        getOperatingHoursService().getFacilitySchedule(facility.id),
        getBookingService().getBookingsForCourtOnDate(courtId, date),
        getMembershipSessionService().listSessionsForDate(facility.id, dateStr).catch(() => [] as MembershipSessionSlot[]),
      ]);
      if (cancelled) return;
      const schedule = override ?? facilitySchedule;
      const day = schedule?.days.find((d) => d.dayOfWeek === dow) ?? null;
      setSlots(day ? computeAvailableSlots(date, day, existing) : []);
      setMembershipSlots(mSlots.filter((m) => m.courtId === courtId));
      setSlotsLoading(false);
    })().catch(() => {
      if (!cancelled) {
        setSlots([]);
        setMembershipSlots([]);
        setSlotsLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [facility, courtId, date]);

  // Resolve the hourly price for every chosen slot.
  useEffect(() => {
    if (!facility || !facilitySportId || selected.length === 0) {
      setPriceByStart({});
      return;
    }
    let cancelled = false;
    Promise.all(
      selected.map((sl) =>
        getPricingService()
          .resolvePrice(facility.id, facilitySportId, courtId || null, date, localHHMM(sl.startTime))
          .then((rule) => [sl.startTime, rule?.amountMinor ?? null] as const)
          .catch(() => [sl.startTime, null] as const),
      ),
    ).then((pairs) => !cancelled && setPriceByStart(Object.fromEntries(pairs)));
    return () => {
      cancelled = true;
    };
  }, [facility, facilitySportId, courtId, date, selected]);

  const currency = "INR";
  const runs = useMemo(() => mergeRuns(selected), [selected]);
  const hours = selected.reduce((sum, sl) => sum + hoursBetween(sl.startTime, sl.endTime), 0);
  // The total is the sum of each slot's own hourly price; unknown if any slot has no price rule.
  const priced = selected.length > 0 && selected.every((sl) => typeof priceByStart[sl.startTime] === "number");
  const totalMinor = priced
    ? Math.round(selected.reduce((sum, sl) => sum + (priceByStart[sl.startTime] as number) * hoursBetween(sl.startTime, sl.endTime), 0))
    : null;
  const priceMinor = totalMinor != null && hours > 0 ? Math.round(totalMinor / hours) : null;
  const timeLabel = runs.length === 0 ? "—" : runs.map((r) => `${hhmm(r.startTime)} – ${hhmm(r.endTime)}`).join(", ");
  const hoursLabel = `${hours} Hour${hours === 1 ? "" : "s"}`;
  // Online payment settles one booking; several separate time ranges are paid at the venue.
  const onlineAllowed = runs.length <= 1;

  const canNext = useCallback(() => {
    if (step === 0) return !!courtId && selected.length > 0;
    if (step === 1) return guestName.trim().length >= 2 && guestPhone.trim().length >= 6;
    return true;
  }, [step, courtId, selected, guestName, guestPhone]);

  async function confirm() {
    if (!facility || !courtId || runs.length === 0) return;
    setSubmitting(true);
    setError(null);
    const online = payMode === "online" && onlineAllowed;
    const created: Booking[] = [];
    try {
      const extra = guestEmail.trim() ? `Email: ${guestEmail.trim()}` : "";
      const finalNotes = [notes.trim(), extra].filter(Boolean).join(" · ") || null;
      // One booking per continuous range, created one after another so a clash on a later range stops there.
      for (const run of runs) {
        created.push(
          await getBookingService().createBooking({
            facilityId: facility.id,
            courtId,
            startTime: run.startTime,
            endTime: run.endTime,
            customerType: "GUEST",
            guestName: guestName.trim(),
            guestPhone: guestPhone.trim() || null,
            notes: finalNotes,
            paymentStatus: "PENDING",
            partySize: Math.max(1, Number(players) || 1),
            paymentMethod: online ? "Online (Razorpay)" : paymentMethod,
          }),
        );
      }
      const b = created[0]!;

      if (online) {
        // The player is not here: no checkout opens on this screen. The panel makes the payment link for this
        // booking (amount taken from the booking on the server) and the player pays from it.
        setLinkBooking(b);
        setBookedRuns(runs.map((r) => ({ startTime: r.startTime, endTime: r.endTime })));
        return;
      }

      setBooked(b);
      setBookedRuns(created.map((x) => ({ startTime: x.startTime, endTime: x.endTime })));
    } catch (err) {
      const msg = err instanceof ServiceError ? err.message : "Unable to create this booking.";
      setError(
        created.length > 0
          ? `${msg} ${created.length} of ${runs.length} time ranges were already booked (${created.map((x) => `${hhmm(x.startTime)} – ${hhmm(x.endTime)}`).join(", ")}) — check the calendar.`
          : msg,
      );
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
        <h1 className="text-xl font-semibold">Booking Confirmed</h1>
        <p className="text-sm text-muted-foreground">
          {sportName} · {court?.name} · {fmtDateLong(date)} ·{" "}
          {(bookedRuns.length > 0 ? bookedRuns : [booked]).map((r) => `${hhmm(r.startTime)} – ${hhmm(r.endTime)}`).join(", ")}
        </p>
        <p className="text-sm text-muted-foreground">
          {booked.paymentStatus === "PAID"
            ? "Payment received online. Nothing to collect at the venue."
            : "Payment is to be collected offline at the venue."}
        </p>
        <div className="flex justify-center gap-2">
          <Button type="button" variant="outline" onClick={() => router.push("/calendar")}>
            Back to Calendar
          </Button>
          <Button
            type="button"
            onClick={() => {
              setBooked(null);
              setStep(0);
              setSelected([]);
              setGuestName("");
              setGuestPhone("");
              setGuestEmail("");
              setNotes("");
              setPayMode("offline");
              setLinkBooking(null);
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
          onClick={() => router.push("/calendar")}
          className="mb-1 inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> Calendar
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
        <div key={step} className="stat-enter rounded-xl border border-border p-5">
          {step === 0 && (
            <div className="space-y-5">
              <div className="grid gap-3 sm:grid-cols-3">
                <div className="space-y-1">
                  <span className="flex items-center gap-1.5 text-xs text-muted-foreground"><Trophy className="h-3.5 w-3.5" /> Sport</span>
                  <SelectField
                    value={facilitySportId}
                    onValueChange={(v) => {
                      setFacilitySportId(v);
                      setCourtId("");
                      setSelected([]);
                    }}
                    ariaLabel="Sport"
                    className={selectFieldCls}
                    options={facilitySports.map((fs) => {
                      const sp = sports.find((x) => x.id === fs.sportId);
                      return { value: fs.id, label: fs.customSportName ?? sp?.name ?? "Sport" };
                    })}
                  />
                </div>
                <label className="space-y-1">
                  <span className="flex items-center gap-1.5 text-xs text-muted-foreground"><MapPin className="h-3.5 w-3.5" /> Location</span>
                  <div className={cn(selectFieldCls, "flex w-full items-center opacity-70")} aria-label="Location">
                    <span className="truncate">{facility.name}</span>
                  </div>
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
                        setSelected([]);
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
                    {courtsForSport.map((c, i) => {
                      const active = courtId === c.id;
                      return (
                        <button
                          key={c.id}
                          type="button"
                          onClick={() => {
                            setCourtId(c.id);
                            setSelected([]);
                          }}
                          className={cn(
                            "stat-enter relative overflow-hidden rounded-lg border p-0 text-left transition hover:-translate-y-0.5",
                            active ? "border-primary ring-2 ring-primary/30" : "border-border hover:border-primary/50",
                          )}
                          style={{ "--stat-delay": `${i * 55}ms` } as React.CSSProperties}
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
                  <p className="mb-2 text-sm font-semibold">
                    Select Time Slot{selected.length > 0 ? ` (${selected.length} selected)` : ""}
                    <span className="ml-2 text-xs font-normal text-muted-foreground">Tap several to book more than one hour.</span>
                  </p>
                  {slotsLoading ? (
                    <p className="text-sm text-muted-foreground">Loading availability…</p>
                  ) : slots.length === 0 ? (
                    <p className="text-sm text-muted-foreground">No slots available on this date.</p>
                  ) : (
                    <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                      {slots.map((s, i) => {
                        const active = selected.some((x) => x.startTime === s.startTime);
                        const blocked = isMembershipBlocked(s, membershipSlots);
                        const bookable = s.available && !blocked;
                        const label = blocked ? "Blocked" : s.available ? "Available" : "Booked";
                        return (
                          <button
                            key={s.startTime}
                            type="button"
                            disabled={!bookable}
                            onClick={() => setSelected((cur) => toggleSlot(cur, s))}
                            aria-pressed={active}
                            style={{ "--stat-delay": `${120 + i * 22}ms` } as React.CSSProperties}
                            className={cn(
                              "stat-enter rounded-lg border px-3 py-2 text-center transition",
                              active
                                ? "border-primary bg-primary/10"
                                : bookable
                                  ? "border-border hover:border-primary/50"
                                  : "cursor-not-allowed border-border bg-muted opacity-60",
                            )}
                          >
                            <p className="text-sm font-medium">{hhmm(s.startTime)}</p>
                            <p
                              className={cn(
                                "text-[11px]",
                                active
                                  ? "text-primary"
                                  : blocked
                                    ? "text-warning"
                                    : s.available
                                      ? "text-success"
                                      : "text-muted-foreground line-through",
                              )}
                            >
                              {blocked ? "Blocked · Membership" : label}
                            </p>
                          </button>
                        );
                      })}
                    </div>
                  )}
                </div>
              )}

              {selected.length > 0 && (
                <div className="flex flex-wrap items-center gap-2 rounded-lg bg-success/10 px-3 py-2 text-sm text-foreground">
                  <Clock className="h-4 w-4 text-success" />
                  Selected Time: <span className="font-medium">{fmtDateLong(date)}</span> ·{" "}
                  <span className="font-medium text-success">
                    {timeLabel} ({hoursLabel})
                  </span>
                  <button type="button" className="ml-auto text-xs text-muted-foreground underline" onClick={() => setSelected([])}>
                    Clear
                  </button>
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
                <span className="text-xs text-muted-foreground">Players</span>
                <Input value={players} onChange={(e) => setPlayers(e.target.value)} inputMode="numeric" />
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
                <Row label="Time" value={timeLabel} />
                <Row label="Duration" value={hoursLabel} />
                <Row label="Players" value={players} />
                {notes && <Row label="Notes" value={notes} />}
                <Row label="Total" value={totalMinor == null ? "—" : formatCurrency(totalMinor, currency)} />
              </dl>
            </div>
          )}

          {step === 3 && (
            <div className="space-y-4">
              <p className="text-sm font-semibold">Payment</p>

              {linkBooking ? (
                <div className="space-y-3">
                  <p className="text-sm text-muted-foreground">
                    Booking created for {sportName} · {court?.name} · {fmtDateLong(date)} · {timeLabel}. It is confirmed once the payment is received.
                  </p>
                  <BookingPaymentLinkPanel
                    facilityId={facility.id}
                    bookingId={linkBooking.id}
                    guestName={guestName}
                    guestPhone={guestPhone.trim() || null}
                    description={`${sportName} · ${court?.name ?? "Court"} · ${fmtDateLong(date)}, ${timeLabel}`}
                  />
                </div>
              ) : (
                <>
                  <div className="space-y-2">
                    <label
                      className={cn(
                        "flex cursor-pointer items-start gap-3 rounded-lg border p-3 text-sm",
                        payMode === "offline" ? "border-primary bg-primary/5" : "border-border",
                      )}
                    >
                      <input type="radio" name="pay-mode" className="mt-0.5" checked={payMode === "offline"} onChange={() => setPayMode("offline")} />
                      <span>
                        <span className="font-medium">Pay at venue</span>
                        <span className="block text-xs text-muted-foreground">
                          Collect {totalMinor == null ? "the amount" : formatCurrency(totalMinor, currency)} at the venue. Booking is created with
                          payment status Pending.
                        </span>
                      </span>
                    </label>
                    <label
                      className={cn(
                        "flex cursor-pointer items-start gap-3 rounded-lg border p-3 text-sm",
                        payMode === "online" ? "border-primary bg-primary/5" : "border-border",
                      )}
                    >
                      <input type="radio" name="pay-mode" className="mt-0.5" checked={payMode === "online" && onlineAllowed} disabled={!onlineAllowed} onChange={() => setPayMode("online")} />
                      <span>
                        <span className="font-medium">Pay Online</span>
                        <span className="block text-xs text-muted-foreground">
                          {onlineAllowed
                            ? `Get a payment link for ${totalMinor == null ? "the amount" : formatCurrency(totalMinor, currency)} to share with the player. They pay on their own phone (UPI / card / net banking) and the booking is confirmed as Paid once the payment goes through.`
                            : "Online payment covers one continuous time range. You picked separate time ranges, so each is booked and paid at the venue."}
                        </span>
                      </span>
                    </label>
                  </div>

                  {(payMode === "offline" || !onlineAllowed) && (
                    <div className="block max-w-xs space-y-1 text-sm">
                      <span className="text-xs text-muted-foreground">Payment method (for your records)</span>
                      <SelectField
                        value={paymentMethod}
                        onValueChange={setPaymentMethod}
                        ariaLabel="Payment method"
                        className={selectFieldCls}
                        options={["Cash", "UPI", "Card", "Bank Transfer", "Other"].map((m) => ({ value: m, label: m }))}
                      />
                    </div>
                  )}
                  {error && <p className="text-sm text-destructive">{error}</p>}
                </>
              )}
            </div>
          )}
        </div>

        {/* Summary sidebar */}
        <aside className="stat-enter h-fit rounded-xl border border-border p-4" style={{ "--stat-delay": "90ms" } as React.CSSProperties}>
          <p className="text-sm font-semibold">Booking Summary</p>
          <div className="mt-3 flex h-28 items-center justify-center rounded-lg bg-gradient-to-br from-emerald-900 to-emerald-700 text-xs text-emerald-200">
            {court?.name ?? "Select a court"}
          </div>
          <dl className="mt-4 space-y-2.5 text-sm">
            <SummaryRow icon={Trophy} label="Sport" value={sportName || "—"} />
            <SummaryRow icon={MapPin} label="Location" value={facility.name} />
            <SummaryRow icon={MapPin} label="Court" value={court?.name ?? "—"} />
            <SummaryRow icon={CalendarDays} label="Date" value={fmtDateLong(date)} />
            <SummaryRow icon={Clock} label="Time" value={timeLabel} />
            <SummaryRow icon={Clock} label="Duration" value={selected.length > 0 ? hoursLabel : "—"} />
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
              <p className="font-medium">{payMode === "online" ? "Pay online" : "Pay at the venue"}</p>
              <p className="text-muted-foreground">
                {payMode === "online" ? "A secure Razorpay payment link is sent to the player" : "Payment is collected offline"}
              </p>
            </div>
          </div>
        </aside>
      </div>

      {/* Footer nav */}
      <div className="flex items-center justify-between">
        {step === 0 ? (
          <Button type="button" variant="outline" onClick={() => router.push("/calendar")}>
            Cancel
          </Button>
        ) : (
          <Button type="button" variant="outline" disabled={linkBooking != null} onClick={() => setStep((s) => s - 1)}>
            Back
          </Button>
        )}
        {step < 3 ? (
          <Button type="button" onClick={() => setStep((s) => s + 1)} disabled={!canNext()}>
            Next: {STEPS[step + 1]} <ChevronRight className="ml-1 h-4 w-4" />
          </Button>
        ) : linkBooking ? (
          <Button type="button" variant="outline" onClick={() => router.push("/calendar")}>
            Go to Calendar
          </Button>
        ) : (
          <Button type="button" onClick={confirm} disabled={submitting}>
            {submitting ? "Processing…" : payMode === "online" && onlineAllowed ? "Create Payment Link" : "Confirm Booking"}
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