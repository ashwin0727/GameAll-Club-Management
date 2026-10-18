"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Check, ChevronRight, Clock, MapPin, CalendarDays, Trophy, Info, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { CourtImage } from "@/components/shared/court-image";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getBookingService } from "@/services/bookings";
import { getPricingService } from "@/services/pricing";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { computeAvailableSlots } from "@/features/bookings/slots";
import { hoursBetween, runsByCourt, toggleSlot } from "@/features/bookings/slot-selection";
import { advanceSummary, needsAdvance } from "@/features/bookings/advance-payment";
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
  // Any number of courts can be picked, each with its own time slots.
  const [courtIds, setCourtIds] = useState<string[]>([]);
  const [date, setDate] = useState(() => new Date());
  // Any number of slots per court; touching ones on the same court become one booking (see mergeRuns).
  const [selectedByCourt, setSelectedByCourt] = useState<Record<string, TimeSlot[]>>({});
  const [slotsByCourt, setSlotsByCourt] = useState<Record<string, TimeSlot[]>>({});
  const [membershipByCourt, setMembershipByCourt] = useState<Record<string, MembershipSessionSlot[]>>({});
  const [slotsLoading, setSlotsLoading] = useState(false);

  const [guestName, setGuestName] = useState("");
  const [guestPhone, setGuestPhone] = useState("");
  const [guestEmail, setGuestEmail] = useState("");
  const [players, setPlayers] = useState("2");
  const [payMode, setPayMode] = useState<"offline" | "online">("offline");
  const [paymentMethod, setPaymentMethod] = useState("Cash");
  const [notes, setNotes] = useState("");

  // Hourly price resolved per selected slot (it can differ by court and time of day), keyed by court + the slot's start.
  const [priceByStart, setPriceByStart] = useState<Record<string, number | null>>({});
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [booked, setBooked] = useState<Booking | null>(null);
  // "Pay Online": the booking exists and a payment link is being shared with the player, who pays on their own phone.
  // One link per booking that needs paying online (a single one for an ordinary online payment).
  const [linkBookings, setLinkBookings] = useState<Booking[]>([]);

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
  const courtName = (id: string) => areas.find((a) => a.id === id)?.name ?? "Court";
  const courtsLabel = courtIds.length > 0 ? courtIds.map(courtName).join(", ") : null;
  const sportName = useMemo(() => {
    const fs = facilitySports.find((x) => x.id === facilitySportId);
    return fs?.customSportName ?? sports.find((s) => s.id === fs?.sportId)?.name ?? "";
  }, [facilitySports, sports, facilitySportId]);

  // Load slots for every picked court on the chosen date.
  useEffect(() => {
    if (!facility || courtIds.length === 0) {
      setSlotsByCourt({});
      setMembershipByCourt({});
      return;
    }
    let cancelled = false;
    setSlotsLoading(true);
    const dateStr = toDateInput(date);
    (async () => {
      const dow = date.getDay();
      const [facilitySchedule, mSlots] = await Promise.all([
        getOperatingHoursService().getFacilitySchedule(facility.id),
        getMembershipSessionService().listSessionsForDate(facility.id, dateStr).catch(() => [] as MembershipSessionSlot[]),
      ]);
      const entries = await Promise.all(
        courtIds.map(async (id) => {
          const [override, existing] = await Promise.all([
            getOperatingHoursService().getPlayingAreaSchedule(id),
            getBookingService().getBookingsForCourtOnDate(id, date),
          ]);
          const schedule = override ?? facilitySchedule;
          const day = schedule?.days.find((d) => d.dayOfWeek === dow) ?? null;
          return [id, day ? computeAvailableSlots(date, day, existing, 60, true) : []] as const;
        }),
      );
      if (cancelled) return;
      setSlotsByCourt(Object.fromEntries(entries));
      setMembershipByCourt(Object.fromEntries(courtIds.map((id) => [id, mSlots.filter((m) => m.courtId === id)])));
      setSlotsLoading(false);
    })().catch(() => {
      if (!cancelled) {
        setSlotsByCourt({});
        setMembershipByCourt({});
        setSlotsLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [facility, courtIds, date]);

  // Every (court, slot) chosen, flattened — what gets priced and totalled.
  const picks = useMemo(
    () => courtIds.flatMap((id) => (selectedByCourt[id] ?? []).map((slot) => ({ courtId: id, slot }))),
    [courtIds, selectedByCourt],
  );
  const pickKey = (courtId: string, startTime: string) => `${courtId}|${startTime}`;

  // Resolve the hourly price for every chosen slot.
  useEffect(() => {
    if (!facility || !facilitySportId || picks.length === 0) {
      setPriceByStart({});
      return;
    }
    let cancelled = false;
    Promise.all(
      picks.map(({ courtId, slot }) =>
        getPricingService()
          .resolvePrice(facility.id, facilitySportId, courtId, date, localHHMM(slot.startTime))
          .then((rule) => [pickKey(courtId, slot.startTime), rule?.amountMinor ?? null] as const)
          .catch(() => [pickKey(courtId, slot.startTime), null] as const),
      ),
    ).then((pairs) => !cancelled && setPriceByStart(Object.fromEntries(pairs)));
    return () => {
      cancelled = true;
    };
  }, [facility, facilitySportId, date, picks]);

  const currency = "INR";
  const runs = useMemo(() => runsByCourt(selectedByCourt, courtIds), [selectedByCourt, courtIds]);
  const hours = picks.reduce((sum, p) => sum + hoursBetween(p.slot.startTime, p.slot.endTime), 0);
  // The total is the sum of each slot's own hourly price; unknown if any slot has no price rule.
  const priced = picks.length > 0 && picks.every((p) => typeof priceByStart[pickKey(p.courtId, p.slot.startTime)] === "number");
  const totalMinor = priced
    ? Math.round(
        picks.reduce((sum, p) => sum + (priceByStart[pickKey(p.courtId, p.slot.startTime)] as number) * hoursBetween(p.slot.startTime, p.slot.endTime), 0),
      )
    : null;
  const priceMinor = totalMinor != null && hours > 0 ? Math.round(totalMinor / hours) : null;
  const timeLabel =
    runs.length === 0
      ? "—"
      : courtIds.length > 1
        ? courtIds
            .filter((id) => runs.some((r) => r.courtId === id))
            .map((id) => `${courtName(id)}: ${runs.filter((r) => r.courtId === id).map((r) => `${hhmm(r.startTime)} – ${hhmm(r.endTime)}`).join(", ")}`)
            .join(" · ")
        : runs.map((r) => `${hhmm(r.startTime)} – ${hhmm(r.endTime)}`).join(", ");
  const hoursLabel = `${hours} Hour${hours === 1 ? "" : "s"}`;
  // Each booking's own price, for working out the advance.
  const runPrices = useMemo(
    () =>
      runs.map((r) => {
        const keys = r.slots.map((sl) => priceByStart[pickKey(r.courtId, sl.startTime)]);
        const priced = keys.length > 0 && keys.every((k) => typeof k === "number");
        const total = priced ? r.slots.reduce((sum, sl) => sum + (priceByStart[pickKey(r.courtId, sl.startTime)] as number) * hoursBetween(sl.startTime, sl.endTime), 0) : null;
        return { startTime: r.startTime, endTime: r.endTime, totalMinor: total == null ? null : Math.round(total) };
      }),
    [runs, priceByStart],
  );
  // A booking longer than an hour is only accepted with a 50% advance paid online.
  const advance = useMemo(() => advanceSummary(runPrices), [runPrices]);
  // Otherwise online payment settles one booking; several separate bookings are paid at the venue.
  const onlineAllowed = advance.required || runs.length <= 1;
  const effectivePayMode: "offline" | "online" = advance.required ? "online" : payMode;

  const canNext = useCallback(() => {
    if (step === 0) return courtIds.length > 0 && picks.length > 0;
    if (step === 1) return guestName.trim().length >= 2 && guestPhone.trim().length >= 6;
    return true;
  }, [step, courtIds, picks, guestName, guestPhone]);

  async function confirm() {
    if (!facility || courtIds.length === 0 || runs.length === 0) return;
    setSubmitting(true);
    setError(null);
    const online = effectivePayMode === "online" && onlineAllowed;
    const created: Booking[] = [];
    try {
      const extra = guestEmail.trim() ? `Email: ${guestEmail.trim()}` : "";
      const finalNotes = [notes.trim(), extra].filter(Boolean).join(" · ") || null;
      // One booking per court and continuous range, created one after another so a clash on a later one stops there.
      for (const run of runs) {
        created.push(
          await getBookingService().createBooking({
            facilityId: facility.id,
            courtId: run.courtId,
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
        // Only the bookings that need an advance get a link; a short one booked alongside is paid at the venue.
        setLinkBookings(advance.required ? created.filter((x) => needsAdvance(x.startTime, x.endTime)) : created);
        return;
      }

      setBooked(b);
    } catch (err) {
      const msg = err instanceof ServiceError ? err.message : "Unable to create this booking.";
      setError(
        created.length > 0
          ? `${msg} ${created.length} of ${runs.length} bookings were already made (${created.map((x) => `${courtName(x.courtId)} ${hhmm(x.startTime)} – ${hhmm(x.endTime)}`).join(", ")}) — check the calendar.`
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
          {sportName} · {courtsLabel} · {fmtDateLong(date)} ·{" "}
          {timeLabel}
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
              setSelectedByCourt({});
              setGuestName("");
              setGuestPhone("");
              setGuestEmail("");
              setNotes("");
              setPayMode("offline");
              setLinkBookings([]);
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
                      setCourtIds([]);
                      setSelectedByCourt({});
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
                        setSelectedByCourt({});
                      }
                    }}
                    className={selectCls}
                  />
                </label>
              </div>

              <div>
                <p className="mb-2 text-sm font-semibold">
                  Select Court
                  <span className="ml-2 text-xs font-normal text-muted-foreground">Pick one or more courts.</span>
                </p>
                {courtsForSport.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No bookable courts for this sport.</p>
                ) : (
                  <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                    {courtsForSport.map((c, i) => {
                      const active = courtIds.includes(c.id);
                      return (
                        <button
                          key={c.id}
                          type="button"
                          onClick={() => {
                            setCourtIds((cur) => (cur.includes(c.id) ? cur.filter((x) => x !== c.id) : [...cur, c.id]));
                            setSelectedByCourt((cur) => {
                              if (!(c.id in cur)) return cur;
                              const rest = { ...cur };
                              delete rest[c.id];
                              return rest;
                            });
                          }}
                          aria-pressed={active}
                          className={cn(
                            "stat-enter relative overflow-hidden rounded-lg border p-0 text-left transition hover:-translate-y-0.5",
                            active ? "border-primary ring-2 ring-primary/30" : "border-border hover:border-primary/50",
                          )}
                          style={{ "--stat-delay": `${i * 55}ms` } as React.CSSProperties}
                        >
                          <div className="h-20">
                            <CourtImage />
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

              {courtIds.length > 0 && (
                <div className="space-y-4">
                  <p className="text-sm font-semibold">
                    Select Time Slot{picks.length > 0 ? ` (${picks.length} selected)` : ""}
                    <span className="ml-2 text-xs font-normal text-muted-foreground">
                      Tap several to book more than one hour{courtIds.length > 1 ? ", on each court" : ""}.
                    </span>
                  </p>
                  {slotsLoading ? (
                    <p className="text-sm text-muted-foreground">Loading availability…</p>
                  ) : (
                    courtIds.map((id) => {
                      const slots = slotsByCourt[id] ?? [];
                      const membershipSlots = membershipByCourt[id] ?? [];
                      const chosen = selectedByCourt[id] ?? [];
                      return (
                        <div key={id} className="space-y-2">
                          {courtIds.length > 1 && (
                            <p className="text-xs font-semibold text-foreground">
                              {courtName(id)}
                              {chosen.length > 0 && <span className="ml-1.5 font-normal text-muted-foreground">({chosen.length} selected)</span>}
                            </p>
                          )}
                          {slots.length === 0 ? (
                            <p className="text-sm text-muted-foreground">No slots available on this date.</p>
                          ) : (
                            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                              {slots.map((s, i) => {
                                const active = chosen.some((x) => x.startTime === s.startTime);
                                const blocked = isMembershipBlocked(s, membershipSlots);
                                const bookable = s.available && !blocked;
                                const label = blocked ? "Blocked" : s.available ? "Available" : "Booked";
                                return (
                                  <button
                                    key={s.startTime}
                                    type="button"
                                    disabled={!bookable}
                                    onClick={() => setSelectedByCourt((cur) => ({ ...cur, [id]: toggleSlot(cur[id] ?? [], s) }))}
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
                      );
                    })
                  )}
                </div>
              )}

              {picks.length > 0 && (
                <div className="flex flex-wrap items-center gap-2 rounded-lg bg-success/10 px-3 py-2 text-sm text-foreground">
                  <Clock className="h-4 w-4 text-success" />
                  Selected Time: <span className="font-medium">{fmtDateLong(date)}</span> ·{" "}
                  <span className="font-medium text-success">
                    {timeLabel} ({hoursLabel})
                  </span>
                  <button type="button" className="ml-auto text-xs text-muted-foreground underline" onClick={() => setSelectedByCourt({})}>
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
                <Row label={courtIds.length > 1 ? "Courts" : "Court"} value={courtsLabel ?? "—"} />
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

              {linkBookings.length > 0 ? (
                <div className="space-y-4">
                  <p className="text-sm text-muted-foreground">
                    Booking created for {sportName} · {courtsLabel} · {fmtDateLong(date)} · {timeLabel}.{" "}
                    {advance.required
                      ? "It is confirmed once the 50% advance is received online; the balance is collected at the venue."
                      : "It is confirmed once the payment is received."}
                  </p>
                  {linkBookings.map((lb) => (
                    <div key={lb.id} className="space-y-1.5">
                      {linkBookings.length > 1 && (
                        <p className="text-xs font-semibold">
                          {courtName(lb.courtId)} · {hhmm(lb.startTime)} – {hhmm(lb.endTime)}
                        </p>
                      )}
                      <BookingPaymentLinkPanel
                        facilityId={facility.id}
                        bookingId={lb.id}
                        guestName={guestName}
                        guestPhone={guestPhone.trim() || null}
                        advance={needsAdvance(lb.startTime, lb.endTime)}
                        description={`${advance.required ? "Advance (50%) · " : ""}${sportName} · ${courtName(lb.courtId)} · ${fmtDateLong(date)}, ${hhmm(lb.startTime)} – ${hhmm(lb.endTime)}`}
                      />
                    </div>
                  ))}
                </div>
              ) : (
                <>
                  {advance.required && (
                    <div className="flex items-start gap-2 rounded-lg border border-primary/30 bg-primary/5 p-3 text-sm" role="note">
                      <Info className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                      <div>
                        <p className="font-medium">50% advance required online</p>
                        <p className="text-xs text-muted-foreground">
                          Bookings longer than 1 hour are accepted only after the player pays 50% in advance through the payment link
                          {advance.dueNowMinor != null && advance.balanceMinor != null
                            ? ` — ${formatCurrency(advance.dueNowMinor, currency)} now, ${formatCurrency(advance.balanceMinor, currency)} at the venue.`
                            : "."}
                        </p>
                      </div>
                    </div>
                  )}
                  <div className="space-y-2">
                    <label
                      className={cn(
                        "flex items-start gap-3 rounded-lg border p-3 text-sm",
                        advance.required ? "cursor-not-allowed opacity-50" : "cursor-pointer",
                        effectivePayMode === "offline" ? "border-primary bg-primary/5" : "border-border",
                      )}
                    >
                      <input type="radio" name="pay-mode" className="mt-0.5" checked={effectivePayMode === "offline"} disabled={advance.required} onChange={() => setPayMode("offline")} />
                      <span>
                        <span className="font-medium">Pay at venue</span>
                        <span className="block text-xs text-muted-foreground">
                          {advance.required
                            ? "Not available for bookings longer than 1 hour — the advance must be paid online."
                            : `Collect ${totalMinor == null ? "the amount" : formatCurrency(totalMinor, currency)} at the venue. Booking is created with payment status Pending.`}
                        </span>
                      </span>
                    </label>
                    <label
                      className={cn(
                        "flex cursor-pointer items-start gap-3 rounded-lg border p-3 text-sm",
                        effectivePayMode === "online" ? "border-primary bg-primary/5" : "border-border",
                      )}
                    >
                      <input type="radio" name="pay-mode" className="mt-0.5" checked={effectivePayMode === "online" && onlineAllowed} disabled={!onlineAllowed} onChange={() => setPayMode("online")} />
                      <span>
                        <span className="font-medium">Pay Online</span>
                        <span className="block text-xs text-muted-foreground">
                          {advance.required
                            ? `Get ${advance.longCount > 1 ? "a payment link for each long booking" : "a payment link"} for the 50% advance${advance.dueNowMinor != null ? ` (${formatCurrency(advance.dueNowMinor, currency)})` : ""} to share with the player. The booking is confirmed once it is paid; the balance is collected at the venue.`
                            : onlineAllowed
                            ? `Get a payment link for ${totalMinor == null ? "the amount" : formatCurrency(totalMinor, currency)} to share with the player. They pay on their own phone (UPI / card / net banking) and the booking is confirmed as Paid once the payment goes through.`
                            : "Online payment covers a single booking. You picked several courts or separate time ranges, so each is booked and paid at the venue."}
                        </span>
                      </span>
                    </label>
                  </div>

                  {(effectivePayMode === "offline" || !onlineAllowed) && (
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
            {courtsLabel ?? "Select a court"}
          </div>
          <dl className="mt-4 space-y-2.5 text-sm">
            <SummaryRow icon={Trophy} label="Sport" value={sportName || "—"} />
            <SummaryRow icon={MapPin} label="Location" value={facility.name} />
            <SummaryRow icon={MapPin} label={courtIds.length > 1 ? "Courts" : "Court"} value={courtsLabel ?? "—"} />
            <SummaryRow icon={CalendarDays} label="Date" value={fmtDateLong(date)} />
            <SummaryRow icon={Clock} label="Time" value={timeLabel} />
            <SummaryRow icon={Clock} label="Duration" value={picks.length > 0 ? hoursLabel : "—"} />
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
            {advance.required && (
              <>
                <div className="mt-1 flex justify-between text-sm font-semibold">
                  <span>Advance Due Online (50%)</span>
                  <span>{advance.dueNowMinor == null ? "—" : formatCurrency(advance.dueNowMinor, currency)}</span>
                </div>
                <div className="mt-1 flex justify-between text-sm text-muted-foreground">
                  <span>Balance at Venue</span>
                  <span>{advance.balanceMinor == null ? "—" : formatCurrency(advance.balanceMinor, currency)}</span>
                </div>
              </>
            )}
          </div>
          <div className="mt-3 flex items-start gap-2 rounded-lg bg-secondary/40 p-2.5 text-xs">
            <Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" />
            <div>
              <p className="font-medium">{effectivePayMode === "online" ? (advance.required ? "50% advance online" : "Pay online") : "Pay at the venue"}</p>
              <p className="text-muted-foreground">
                {effectivePayMode === "online" ? "A secure Razorpay payment link is sent to the player" : "Payment is collected offline"}
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
          <Button type="button" variant="outline" disabled={linkBookings.length > 0} onClick={() => setStep((s) => s - 1)}>
            Back
          </Button>
        )}
        {step < 3 ? (
          <Button type="button" onClick={() => setStep((s) => s + 1)} disabled={!canNext()}>
            Next: {STEPS[step + 1]} <ChevronRight className="ml-1 h-4 w-4" />
          </Button>
        ) : linkBookings.length > 0 ? (
          <Button type="button" variant="outline" onClick={() => router.push("/calendar")}>
            Go to Calendar
          </Button>
        ) : (
          <Button type="button" onClick={confirm} disabled={submitting}>
            {submitting ? "Processing…" : effectivePayMode === "online" && onlineAllowed ? "Create Payment Link" : "Confirm Booking"}
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