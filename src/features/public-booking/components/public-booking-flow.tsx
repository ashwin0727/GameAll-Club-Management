"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  CalendarDays,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Check,
  CircleAlert,
  CircleCheck,
  Download,
  LayoutGrid,
  Lock,
  Mail,
  MapPin,
  Phone,
  Share2,
  UserRound,
  WalletCards,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { CourtImage } from "@/components/shared/court-image";
import { resolveFacilityHeroImage } from "../hero-image";
import {
  HoldExpiredError,
  SlotUnavailableError,
  createPublicCheckout,
  createPublicGuestBooking,
  downloadPublicBookingInvoice,
  getPublicBookingFacility,
  getPublicBookingReceipt,
  getPublicCourtAvailability,
  verifyPublicCheckout,
  type PublicBookingReceipt,
} from "../public-booking";
import { isCheckoutCancellation, isCheckoutFailure, openRazorpayCheckout } from "@/features/payments/razorpay-checkout";
import { samePick, summarise, togglePick, type Pick, type PickSummary } from "../picks";
import { clearPending, loadPending, savePending } from "../pending";
import {
  EMPTY_GUEST,
  durationLabel,
  formatBookingDate,
  formatMoney,
  formatSlotRange,
  localPhonePart,
  toDateParam,
  validateGuest,
  withDialCode,
  DEFAULT_DIAL_CODE,
  type GuestFieldErrors,
} from "../guest-form";
import { PublicBookingHeader } from "./public-booking-header";
import { MobileOtpVerifier } from "@/features/mobile-otp/components/mobile-otp-verifier";
import { tenDigitMobile } from "@/features/mobile-otp/mobile-otp";
import { BOOKING_PURPOSES, type PublicBookingConfirmation, type PublicBookingCourt, type PublicBookingFacility, type PublicGuestDetails } from "../types";

type Step = "select" | "details" | "review" | "pay" | "done";

const STEPS: { id: Step; label: string }[] = [
  { id: "select", label: "Choose Court & Time" },
  { id: "details", label: "Guest Details" },
  { id: "review", label: "Review & Confirm" },
  { id: "pay", label: "Payment" },
  { id: "done", label: "Booking Confirmed" },
];

/** Next 14 days, starting today — the window a player can book into. */
function upcomingDates(): Date[] {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Array.from({ length: 14 }, (_, i) => {
    const d = new Date(today);
    d.setDate(today.getDate() + i);
    return d;
  });
}

/**
 * Reports the document height to the parent frame so the embed script can
 * size the iframe to its content — otherwise a fixed-height frame either
 * clips the form or leaves dead space under it. Runs only when embedded.
 */
function useEmbedAutoHeight(enabled: boolean) {
  useEffect(() => {
    if (!enabled || typeof window === "undefined" || window.parent === window) return;

    const post = () => {
      const height = document.documentElement.scrollHeight;
      window.parent.postMessage({ type: "gameall:height", height }, "*");
    };

    post();
    const observer = new ResizeObserver(post);
    observer.observe(document.documentElement);
    return () => observer.disconnect();
  }, [enabled]);
}

export function PublicBookingFlow({
  facilityId,
  embedded = false,
  initialSportId,
}: {
  facilityId: string;
  /** Rendered inside a club's own site: no page chrome, height reported out. */
  embedded?: boolean;
  initialSportId?: string;
}) {
  useEmbedAutoHeight(embedded);
  const [facility, setFacility] = useState<PublicBookingFacility | null>(null);
  const [facilityLoading, setFacilityLoading] = useState(true);

  const [sportId, setSportId] = useState<string>("");
  const dates = useMemo(upcomingDates, []);
  const [date, setDate] = useState<Date>(() => dates[0]!);

  const [courts, setCourts] = useState<PublicBookingCourt[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);

  // Any number of courts, and any number of hours on each; every hour ticked is one entry in picks.
  const [picks, setPicks] = useState<Pick[]>([]);
  const [courtIds, setCourtIds] = useState<string[]>([]);
  const summary = useMemo(() => (picks.length > 0 ? summarise(picks) : null), [picks]);
  const [guest, setGuest] = useState<PublicGuestDetails>(EMPTY_GUEST);
  // Set once the guest has proven they own guest.phone by SMS; the booking function refuses to book without it.
  const [mobileProof, setMobileProof] = useState<{ proof: string; phone: string } | null>(null);
  const [errors, setErrors] = useState<GuestFieldErrors>({});

  const [step, setStep] = useState<Step>("select");
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [confirmations, setConfirmations] = useState<PublicBookingConfirmation[]>([]);
  // Bookings longer than an hour wait here, held, until their 50% advance is paid online.
  const [pending, setPending] = useState<PendingItem[]>([]);
  const pendingRef = useRef<PendingItem[]>([]);
  pendingRef.current = pending;
  const [otherConfirmations, setOtherConfirmations] = useState<PublicBookingConfirmation[]>([]);
  const [payingId, setPayingId] = useState<string | null>(null);
  const [payError, setPayError] = useState<string | null>(null);
  const [partialNote, setPartialNote] = useState<string | null>(null);
  const bookingPhone = useRef("");
  const [summaryOpen, setSummaryOpen] = useState(false);
  const [agreed, setAgreed] = useState(false);

  useEffect(() => {
    let active = true;
    getPublicBookingFacility(facilityId)
      .then((f) => {
        if (!active) return;
        setFacility(f);
        if (f?.sports.length) {
          const preset = initialSportId && f.sports.some((s) => s.facilitySportId === initialSportId);
          setSportId(preset ? initialSportId! : f.sports[0]!.facilitySportId);
        }
      })
      .finally(() => active && setFacilityLoading(false));
    return () => {
      active = false;
    };
  }, [facilityId, initialSportId]);

  const loadSlots = useCallback(
    async (pickFirstCourt: boolean) => {
      if (!sportId) return;
      setSlotsLoading(true);
      try {
        const list = await getPublicCourtAvailability(facilityId, sportId, toDateParam(date));
        setCourts(list);
        if (pickFirstCourt) {
          const first = list.find((c) => c.slots.some((sl) => sl.available)) ?? list[0];
          setCourtIds(first ? [first.courtId] : []);
        }
      } finally {
        setSlotsLoading(false);
      }
    },
    [facilityId, sportId, date],
  );

  useEffect(() => {
    // Changing sport or date invalidates every court and slot already picked.
    setPicks([]);
    setCourtIds([]);
    void loadSlots(true);
  }, [loadSlots]);

  function toggleCourt(id: string) {
    if (courtIds.includes(id)) {
      setCourtIds(courtIds.filter((x) => x !== id));
      setPicks((cur) => cur.filter((p) => p.courtId !== id));
    } else {
      setCourtIds([...courtIds, id]);
    }
  }

  const sport = facility?.sports.find((s) => s.facilitySportId === sportId) ?? null;
  const sportName = sport?.name ?? "";

  function goToDetails() {
    if (picks.length === 0) return;
    setFormError(null);
    setStep("details");
  }

  function goToReview() {
    const found = validateGuest(guest);
    if (!found.phone && mobileProof?.phone !== tenDigitMobile(guest.phone)) {
      found.phone = "Please verify your mobile number with the OTP we text you.";
    }
    setErrors(found);
    if (Object.keys(found).length > 0) return;
    setFormError(null);
    setStep("review");
  }

  /** Send the player back to slot selection after losing a race for a slot. */
  function returnToSelection(message: string) {
    setPicks([]);
    setStep("select");
    setFormError(message);
    void loadSlots(false);
  }

  async function confirm() {
    if (!summary || submitting) return;
    setSubmitting(true);
    setFormError(null);
    // One booking per court and continuous stretch, made one after another so a clash on a later one stops there.
    const made: PublicBookingConfirmation[] = [];
    let failure: Error | null = null;
    try {
      for (const r of summary.requests) {
        made.push(
          await createPublicGuestBooking({
            facilityId,
            courtId: r.courtId,
            startTime: r.startTime,
            endTime: r.endTime,
            guest,
            mobileProof: mobileProof?.proof,
          }),
        );
      }
    } catch (e) {
      failure = e instanceof Error ? e : new Error("Something went wrong. Please try again.");
    }

    if (failure && made.length === 0) {
      if (failure instanceof SlotUnavailableError) {
        returnToSelection("Sorry, this court is no longer available. Please choose another time.");
      } else if (failure.message.startsWith("Please verify your mobile")) {
        // The 30-minute proof lapsed — verify again.
        setMobileProof(null);
        setErrors({ phone: failure.message });
        setStep("details");
      } else {
        setFormError(failure.message);
      }
      setSubmitting(false);
      return;
    }

    bookingPhone.current = guest.phone;
    const note = failure
      ? `${failure instanceof SlotUnavailableError ? "One of the courts was taken just now." : failure.message} ${made.length} of ${summary.requests.length} bookings were made — the rest were not.`
      : null;
    setPartialNote(note);
    const advance = made.filter((c) => c.advanceRequired);
    const others = made.filter((c) => !c.advanceRequired);
    if (advance.length === 0) {
      setConfirmations(made);
      setStep("done");
    } else {
      setOtherConfirmations(others);
      setPending(advance.map((c) => ({ confirmation: c, state: "waiting" as const })));
      setPayError(null);
      savePending(facilityId, { phone: guest.phone, advance, others, notice: note });
      setStep("pay");
    }
    setSubmitting(false);
  }

  function markPending(bookingId: string, state: PendingItem["state"]) {
    setPending((cur) => cur.map((i) => (i.confirmation.bookingId === bookingId ? { ...i, state } : i)));
  }

  /**
   * Opens Razorpay Checkout ONCE for the advance of every held booking (however many courts and times), then has the
   * server verify the result and confirm them all together.
   */
  async function payAdvance() {
    const items = pendingRef.current.filter((i) => i.state === "waiting");
    if (items.length === 0 || payingId) return;
    const ids = items.map((i) => i.confirmation.bookingId);
    const phone = bookingPhone.current;
    setPayError(null);
    setPayingId(ids[0]!);
    try {
      const checkout = await createPublicCheckout({ bookingIds: ids, phone });
      if (checkout.paid) {
        for (const id of ids) markPending(id, "confirmed");
        return;
      }
      const first = items[0]!.confirmation;
      const outcome = await openRazorpayCheckout(
        {
          keyId: checkout.keyId!,
          razorpayOrderId: checkout.razorpayOrderId!,
          amount: checkout.amount!,
          currency: checkout.currency ?? "INR",
          paymentOrderId: checkout.paymentOrderId!,
          receipt: checkout.receipt ?? "",
        },
        {
          description: `${sportName} · ${items.length > 1 ? `${items.length} courts` : first.courtName} — 50% advance`,
          prefill: { name: first.guestName, contact: phone },
        },
      );
      const result = await verifyPublicCheckout({
        bookingIds: ids,
        phone,
        paymentOrderId: checkout.paymentOrderId!,
        razorpayOrderId: checkout.razorpayOrderId!,
        razorpayPaymentId: outcome.razorpayPaymentId,
        razorpaySignature: outcome.razorpaySignature,
      });
      if (result.confirmed) for (const id of ids) markPending(id, "confirmed");
      else setPayError("Your payment went through, but the booking isn't confirmed yet. This page will update in a moment.");
    } catch (e) {
      if (isCheckoutCancellation(e)) {
        // Closed Checkout without paying — nothing to report, the button is still there.
      } else if (isCheckoutFailure(e)) {
        setPayError(e.description || "The payment didn't go through. Please try again.");
      } else if (e instanceof HoldExpiredError) {
        for (const id of ids) markPending(id, "expired");
      } else {
        setPayError(e instanceof Error ? e.message : "We couldn't start the payment. Please try again.");
      }
    } finally {
      setPayingId(null);
    }
  }

  function bookAgain() {
    clearPending(facilityId);
    setPending([]);
    setOtherConfirmations([]);
    setPartialNote(null);
    setPicks([]);
    setStep("select");
    void loadSlots(true);
  }

  // Back from the payment page (or a refresh): pick up the bookings that are still waiting on their advance.
  useEffect(() => {
    const stored = loadPending(facilityId);
    if (!stored) return;
    bookingPhone.current = stored.phone;
    setOtherConfirmations(stored.others);
    setPartialNote(stored.notice);
    setPending(stored.advance.map((c) => ({ confirmation: c, state: "waiting" as const })));
    setStep("pay");
  }, [facilityId]);

  // While waiting, ask the server whether each held booking has been confirmed (or has lapsed).
  useEffect(() => {
    if (step !== "pay") return;
    let cancelled = false;
    let running = false;
    const check = async () => {
      if (running) return;
      running = true;
      try {
        for (const item of pendingRef.current.filter((i) => i.state === "waiting")) {
          const status = await getPublicBookingReceipt(item.confirmation.bookingId, bookingPhone.current);
          if (cancelled) return;
          if (status?.confirmed) markPending(item.confirmation.bookingId, "confirmed");
          else if (!status || status.cancelled) markPending(item.confirmation.bookingId, "expired");
        }
      } finally {
        running = false;
      }
    };
    void check();
    const timer = setInterval(() => void check(), 4000);
    const onFocus = () => void check();
    window.addEventListener("focus", onFocus);
    return () => {
      cancelled = true;
      clearInterval(timer);
      window.removeEventListener("focus", onFocus);
    };
  }, [step]);

  // Once nothing is waiting any more, move on to the confirmation (or stay to offer "Book Again" if all lapsed).
  useEffect(() => {
    if (step !== "pay" || pending.length === 0 || pending.some((i) => i.state === "waiting")) return;
    const confirmed = pending.filter((i) => i.state === "confirmed").map((i) => i.confirmation);
    if (confirmed.length === 0) return;
    const lapsed = pending.length - confirmed.length;
    if (lapsed > 0) {
      setPartialNote((cur) => [cur, `${lapsed} booking${lapsed === 1 ? "" : "s"} lapsed because the advance wasn't paid in time.`].filter(Boolean).join(" "));
    }
    setConfirmations([...confirmed, ...otherConfirmations]);
    clearPending(facilityId);
    setStep("done");
  }, [pending, step, otherConfirmations, facilityId]);

  if (facilityLoading) return <FlowSkeleton />;

  if (!facility) {
    return (
      <Notice
        tone="error"
        title="We Couldn't Find This Venue"
        message="The booking link may be incorrect or no longer active."
      />
    );
  }

  if (facility.sports.length === 0) {
    return (
      <Notice
        tone="error"
        title="No Courts Available"
        message="This venue isn't accepting online bookings right now."
      />
    );
  }

  // Only the details step: step 1 has the sticky bar beneath it, and the
  // review page now carries its own Booking Details and Payment Details
  // panels, which this would only repeat.
  const showSummaryPanel = Boolean(summary) && step === "details";

  if (step === "done" && confirmations.length > 0) {
    return <Confirmed confirmations={confirmations} facility={facility} embedded={embedded} notice={partialNote} phone={bookingPhone.current} />;
  }

  return (
    <div className={cn("mx-auto w-full max-w-5xl px-4", embedded ? "py-4" : "py-6 sm:py-10")}>
      <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
        {/* The embed sits inside the club's own site, which already carries
            their branding and contact details — repeating ours would be
            noise. On our hosted page the header belongs. */}
        {!embedded && (
          <PublicBookingHeader
            helpPhone={facility.helpPhone}
            facilityName={facility.facilityName}
            city={facility.city}
          />
        )}

        <div className="px-4 py-5 sm:px-8 sm:py-6">
          <StepBar
            current={step}
            withPayment={Boolean(summary?.advanceRequired) || pending.length > 0 || confirmations.some((c) => c.advanceRequired)}
          />

          <div className="mt-6">
            <h1 className="text-lg font-semibold tracking-tight sm:text-2xl">Book Your Court</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {step === "select"
                ? "Quick and easy court booking for everyone."
                : step === "details"
                  ? "Tell us who's playing."
                  : step === "pay"
                    ? "Pay the advance to confirm your court."
                    : "Check everything over before you confirm."}
            </p>
          </div>

          {/* Two columns only when the summary panel is actually there.
              Declaring the second column unconditionally left an empty
              18rem reserved beside step 1, which the slot rail stopped
              short of — dead space to the right of the times. */}
          <div
            className={cn(
              "mt-5 gap-6",
              showSummaryPanel && "lg:grid lg:grid-cols-[minmax(0,1fr)_18rem] lg:items-start",
            )}
          >
            <div className="min-w-0">
              {formError && step === "select" && (
                <Notice tone="error" title="That Slot Just Went" message={formError} className="mb-4" />
              )}

              {step === "select" && (
                <SelectStep
                  facility={facility}
                  sportId={sportId}
                  onSportChange={setSportId}
                  dates={dates}
                  date={date}
                  onDateChange={setDate}
                  courts={courts}
                  loading={slotsLoading}
                  courtIds={courtIds}
                  onToggleCourt={toggleCourt}
                  picks={picks}
                  onTogglePick={(p) => setPicks((cur) => togglePick(cur, p))}
                  currency={facility.currency}
                />
              )}

              {step === "details" && (
                <DetailsStep
                  guest={guest}
                  errors={errors}
                  onChange={setGuest}
                  mobileVerified={mobileProof?.phone === tenDigitMobile(guest.phone)}
                  onMobileVerified={(proof, phone) => {
                    if (proof) setMobileProof({ proof, phone });
                    setErrors((e) => ({ ...e, phone: undefined }));
                  }}
                  onMobileReset={() => setMobileProof(null)}
                />
              )}

              {step === "pay" && (
                <PayStep items={pending} payingId={payingId} error={payError} notice={partialNote} onPay={() => void payAdvance()} onBookAgain={bookAgain} />
              )}

              {step === "review" && summary && (
                <ReviewStep
                  facility={facility}
                  sportName={sportName}
                  summary={summary}
                  guest={guest}
                  error={formError}
                  agreed={agreed}
                  onAgreedChange={setAgreed}
                />
              )}
            </div>

            {/* The desktop summary panel is for the later steps: on step 1
                the sticky bar below already shows the same figures, and two
                copies of them side by side reads as a mistake. */}
            {showSummaryPanel && summary && (
              <SummaryPanel
                open={summaryOpen}
                onToggle={() => setSummaryOpen((v) => !v)}
                facility={facility}
                sportName={sportName}
                summary={summary}
              />
            )}
          </div>
        </div>

        <BookingActionBar
          step={step}
          facility={facility}
          sportName={sportName}
          summary={summary}
          submitting={submitting}
          agreed={agreed}
          onBack={() => {
            setFormError(null);
            setStep(step === "review" ? "details" : "select");
          }}
          onNext={step === "select" ? goToDetails : step === "details" ? goToReview : confirm}
        />
      </div>
    </div>
  );
}

/** The Payment step only exists for a booking that needs an online advance (longer than an hour). */
function StepBar({ current, withPayment }: { current: Step; withPayment: boolean }) {
  const steps = STEPS.filter((s) => s.id !== "pay" || withPayment);
  const index = steps.findIndex((s) => s.id === current);
  return (
    <ol className="flex items-center" aria-label="Booking Steps">
      {steps.map((s, i) => {
        const done = i < index;
        const active = i === index;
        return (
          <li key={s.id} className="flex min-w-0 flex-1 items-center gap-2 last:flex-none">
            <span
              className={cn(
                "flex h-7 w-7 shrink-0 items-center justify-center rounded-full border text-xs font-semibold transition-colors",
                active && "border-primary bg-primary text-primary-foreground",
                done && "border-primary bg-primary/15 text-primary",
                !active && !done && "border-border bg-background text-muted-foreground",
              )}
              aria-current={active ? "step" : undefined}
            >
              {done ? <CircleCheck className="h-4 w-4" aria-hidden /> : i + 1}
            </span>
            {/* Labels are desktop-only: at phone widths four of them cannot
                fit legibly, and the numbered circles already say where you
                are. */}
            <span
              className={cn(
                "hidden truncate text-xs lg:inline",
                active ? "font-medium text-foreground" : "text-muted-foreground",
              )}
            >
              {s.label}
            </span>
            {i < steps.length - 1 && (
              <span
                className={cn("h-px flex-1 transition-colors", done ? "bg-primary/40" : "bg-border")}
                aria-hidden
              />
            )}
          </li>
        );
      })}
    </ol>
  );
}

function SelectStep({
  facility,
  sportId,
  onSportChange,
  dates,
  date,
  onDateChange,
  courts,
  loading,
  courtIds,
  onToggleCourt,
  picks,
  onTogglePick,
  currency,
}: {
  facility: PublicBookingFacility;
  sportId: string;
  onSportChange: (v: string) => void;
  dates: Date[];
  date: Date;
  onDateChange: (d: Date) => void;
  courts: PublicBookingCourt[];
  loading: boolean;
  courtIds: string[];
  onToggleCourt: (courtId: string) => void;
  picks: Pick[];
  onTogglePick: (p: Pick) => void;
  currency: string;
}) {
  const [showAllCourts, setShowAllCourts] = useState(false);
  // Courts have no photograph of their own: show the venue's own image, else the sport's artwork (e.g. the football
  // turf), and the green COURT panel when neither exists or the file fails to load.
  const courtImage = resolveFacilityHeroImage(facility, facility.sports.find((s) => s.facilitySportId === sportId) ?? null).src;

  // Any number of courts can be ticked; each one gets its own row of times below, and any number of times on each.
  const chosenCourts = courtIds.map((id) => courts.find((c) => c.courtId === id)).filter((c): c is PublicBookingCourt => Boolean(c));

  const VISIBLE = 3;
  const visibleCourts = showAllCourts ? courts : courts.slice(0, VISIBLE);
  const hasMoreCourts = courts.length > VISIBLE;

  return (
    <div className="space-y-6">
      {/* Sport / facility / date. The facility is fixed by the link, so it
          renders as a disabled control rather than being hidden — the player
          should still see which venue they are booking. */}
      <div className="grid gap-3 sm:grid-cols-3">
        <Picker id="sport" label="Sport" icon={LayoutGrid}>
          <Select value={sportId} onValueChange={onSportChange}>
            <SelectTrigger id="sport" aria-label="Sport">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {facility.sports.map((s) => (
                <SelectItem key={s.facilitySportId} value={s.facilitySportId}>
                  {s.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Picker>

        <Picker id="facility" label="Facility" icon={MapPin}>
          <Select value={facility.facilityId} disabled>
            <SelectTrigger id="facility" aria-label="Facility">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={facility.facilityId}>{facility.facilityName}</SelectItem>
            </SelectContent>
          </Select>
        </Picker>

        <Picker id="date" label="Date" icon={CalendarDays}>
          <Select value={toDateParam(date)} onValueChange={(v) => onDateChange(new Date(`${v}T00:00:00`))}>
            <SelectTrigger id="date" aria-label="Date">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {dates.map((d) => (
                <SelectItem key={toDateParam(d)} value={toDateParam(d)}>
                  {d.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric", weekday: "short" })}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Picker>
      </div>

      <section>
        <div className="mb-1 flex items-end justify-between gap-3">
          <div>
            <h2 className="text-sm font-semibold">Select Courts</h2>
            <p className="text-xs text-muted-foreground">Pick one or more courts for the selected date</p>
          </div>
          {hasMoreCourts && (
            <button
              type="button"
              onClick={() => setShowAllCourts((v) => !v)}
              className="shrink-0 text-xs font-medium text-primary hover:underline"
            >
              {showAllCourts ? "Show less" : "View All"}
            </button>
          )}
        </div>

        {loading ? (
          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-40 rounded-xl" />
            ))}
          </div>
        ) : courts.length === 0 ? (
          <p className="mt-3 rounded-lg border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
            No courts are open on this date. Try another day.
          </p>
        ) : (
          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {visibleCourts.map((court) => (
              <CourtCard
                key={court.courtId}
                court={court}
                imageUrl={courtImage}
                currency={currency}
                selected={courtIds.includes(court.courtId)}
                onSelect={() => onToggleCourt(court.courtId)}
              />
            ))}
            {hasMoreCourts && !showAllCourts && (
              <button
                type="button"
                onClick={() => setShowAllCourts(true)}
                className="flex min-h-40 flex-col items-center justify-center gap-1.5 rounded-xl border border-dashed border-border text-muted-foreground transition-colors hover:border-primary/50 hover:text-foreground"
              >
                <LayoutGrid className="h-5 w-5" aria-hidden />
                <span className="text-sm font-medium">View All Courts</span>
                <span className="text-[11px]">See all courts</span>
              </button>
            )}
          </div>
        )}
      </section>

      <section>
        <h2 className="text-sm font-semibold">Select Time Slots</h2>
        <p className="text-xs text-muted-foreground">
          All times shown in IST. Tap several to book more than one hour{chosenCourts.length > 1 ? ", on each court" : ""}.
        </p>

        {loading ? (
          <div className="mt-3 flex gap-2">
            {[0, 1, 2, 3, 4].map((i) => (
              <Skeleton key={i} className="h-14 w-32 shrink-0 rounded-xl" />
            ))}
          </div>
        ) : chosenCourts.length === 0 ? (
          <p className="mt-3 rounded-lg border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
            Choose a court above to see its times.
          </p>
        ) : (
          chosenCourts.map((court) => (
            <div key={court.courtId} className="mt-3">
              {chosenCourts.length > 1 && <p className="text-xs font-semibold">{court.courtName}</p>}
              {court.slots.length === 0 ? (
                <p className="mt-1 rounded-lg border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
                  No times are open on this court. Try another court or date.
                </p>
              ) : (
                <SlotRail court={court} currency={currency} picks={picks} onTogglePick={onTogglePick} />
              )}
            </div>
          ))
        )}
      </section>
    </div>
  );
}

/** Label + control, matching the design's three pickers. */
function Picker({
  id,
  label,
  icon: Icon,
  children,
}: {
  id: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id} className="flex items-center gap-1.5 text-xs text-muted-foreground">
        <Icon className="h-3.5 w-3.5" aria-hidden />
        {label}
      </Label>
      {children}
    </div>
  );
}

function CourtCard({
  court,
  imageUrl,
  currency,
  selected,
  onSelect,
}: {
  court: PublicBookingCourt;
  /** The picture to show if there is one; otherwise (or if it fails to load) the green COURT panel. */
  imageUrl?: string | null;
  currency: string;
  selected: boolean;
  onSelect: () => void;
}) {
  const free = court.slots.filter((s) => s.available);
  // "from" price: the cheapest hour still open, which is what the player
  // will actually pay if they take the first thing available.
  const fromPrice = free.length ? Math.min(...free.map((s) => s.priceMinor)) : null;

  return (
    <button
      type="button"
      onClick={onSelect}
      aria-pressed={selected}
      className={cn(
        "group relative overflow-hidden rounded-xl border text-left transition-colors",
        selected ? "border-primary ring-1 ring-primary" : "border-border hover:border-primary/40",
      )}
    >
      <div className="relative aspect-[3/1] w-full bg-muted">
        <CourtImage src={imageUrl} alt={court.courtName} />
        {selected && (
          <span className="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full bg-primary text-primary-foreground">
            <CircleCheck className="h-4 w-4" aria-hidden />
          </span>
        )}
      </div>
      <div className="p-2.5">
        <p className="truncate text-sm font-semibold">{court.courtName}</p>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {fromPrice == null ? "Fully booked" : `${formatMoney(fromPrice, currency)} / hour`}
        </p>
      </div>
    </button>
  );
}

/** Horizontally scrolling time slots, with arrows on pointer devices. Any number can be ticked. */
function SlotRail({
  court,
  currency,
  picks,
  onTogglePick,
}: {
  court: PublicBookingCourt;
  currency: string;
  picks: Pick[];
  onTogglePick: (p: Pick) => void;
}) {
  const railRef = useRef<HTMLDivElement>(null);

  const scrollBy = (direction: 1 | -1) => {
    railRef.current?.scrollBy({ left: direction * 240, behavior: "smooth" });
  };

  return (
    <div className="mt-1 flex items-center gap-2">
      <RailButton direction="left" onClick={() => scrollBy(-1)} />
      <div
        ref={railRef}
        className="flex flex-1 snap-x gap-2 overflow-x-auto scroll-smooth pb-1"
      >
        {court.slots.map((slot) => {
          const pick: Pick = {
            courtId: court.courtId,
            courtName: court.courtName,
            startTime: slot.startTime,
            endTime: slot.endTime,
            priceMinor: slot.priceMinor,
          };
          const active = picks.some((p) => samePick(p, pick));
          return (
            <button
              key={slot.startTime}
              type="button"
              disabled={!slot.available}
              aria-pressed={active}
              onClick={() => onTogglePick(pick)}
              className={cn(
                "min-h-14 w-32 shrink-0 snap-start rounded-xl border px-2 py-2 text-center transition-colors",
                !slot.available && "cursor-not-allowed border-dashed opacity-55",
                slot.available && !active && "border-border hover:border-primary/50",
                active && "border-primary bg-primary/10",
              )}
            >
              <span className="block text-xs font-medium">{formatSlotRange(slot.startTime, slot.endTime)}</span>
              <span className="mt-0.5 block text-[11px] text-muted-foreground">
                {slot.available ? formatMoney(slot.priceMinor, currency) : "Unavailable"}
              </span>
            </button>
          );
        })}
      </div>
      <RailButton direction="right" onClick={() => scrollBy(1)} />
    </div>
  );
}

function RailButton({ direction, onClick }: { direction: "left" | "right"; onClick: () => void }) {
  const Icon = direction === "left" ? ChevronLeft : ChevronRight;
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={direction === "left" ? "Earlier times" : "Later times"}
      // Hidden on touch, where swiping the rail is the natural gesture.
      className="hidden h-8 w-8 shrink-0 items-center justify-center rounded-full border border-border text-muted-foreground transition-colors hover:border-primary/50 hover:text-foreground sm:flex"
    >
      <Icon className="h-4 w-4" aria-hidden />
    </button>
  );
}

function DetailsStep({
  guest,
  errors,
  onChange,
  mobileVerified,
  onMobileVerified,
  onMobileReset,
}: {
  guest: PublicGuestDetails;
  errors: GuestFieldErrors;
  onChange: (g: PublicGuestDetails) => void;
  mobileVerified: boolean;
  onMobileVerified: (proof: string | undefined, phone: string) => void;
  onMobileReset: () => void;
}) {
  const set = (key: keyof PublicGuestDetails) => (value: string) => onChange({ ...guest, [key]: value });

  return (
    <div className="space-y-5">
      <div className="grid gap-4 sm:grid-cols-2">
        <Field id="fullName" label="Full Name" required error={errors.fullName}>
          <IconInput
            id="fullName"
            icon={UserRound}
            value={guest.fullName}
            onChange={set("fullName")}
            autoComplete="name"
            placeholder="Enter your full name"
            invalid={Boolean(errors.fullName)}
          />
        </Field>

        <Field id="phone" label="Mobile Number" required error={errors.phone}>
          <PhoneInput
            id="phone"
            value={guest.phone}
            onChange={set("phone")}
            autoComplete="tel"
            placeholder="Enter 10-digit mobile number"
            invalid={Boolean(errors.phone)}
          />
          <MobileOtpVerifier
            phone={guest.phone}
            purpose="booking"
            verified={mobileVerified}
            onVerified={onMobileVerified}
            onReset={onMobileReset}
          />
        </Field>

        <Field id="email" label="Email Address" hint="Optional" error={errors.email}>
          <IconInput
            id="email"
            icon={Mail}
            type="email"
            value={guest.email}
            onChange={set("email")}
            autoComplete="email"
            placeholder="Enter your email address"
            invalid={Boolean(errors.email)}
          />
        </Field>

        <Field id="altPhone" label="Alternate Phone" hint="Optional" error={errors.altPhone}>
          <PhoneInput
            id="altPhone"
            value={guest.altPhone}
            onChange={set("altPhone")}
            placeholder="Enter alternate number"
            invalid={Boolean(errors.altPhone)}
          />
        </Field>

        <div className="sm:col-span-2">
          <Field id="address" label="Address" hint="Optional">
            <IconInput
              id="address"
              icon={MapPin}
              value={guest.address}
              onChange={set("address")}
              autoComplete="street-address"
              placeholder="Enter your address"
            />
          </Field>
        </div>
      </div>

      <div className="border-t border-border pt-5">
        <h2 className="text-sm font-semibold">
          Additional Information <span className="font-normal text-muted-foreground">(Optional)</span>
        </h2>

        <div className="mt-4 grid gap-4 sm:grid-cols-2">
          <Field id="purpose" label="Purpose of Booking">
            <Select
              value={guest.purpose || undefined}
              onValueChange={(v) => set("purpose")(v)}
            >
              <SelectTrigger id="purpose" aria-label="Purpose of Booking">
                <SelectValue placeholder="Select purpose" />
              </SelectTrigger>
              <SelectContent>
                {BOOKING_PURPOSES.map((p) => (
                  <SelectItem key={p} value={p}>
                    {p}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>

          <Field id="specialRequest" label="Special Request">
            <Textarea
              id="specialRequest"
              rows={3}
              value={guest.specialRequest}
              onChange={(e) => set("specialRequest")(e.target.value)}
              placeholder="Anything we should know?&#10;e.g., Need shuttlecocks, equipment, etc."
            />
          </Field>
        </div>
      </div>
    </div>
  );
}

/** Text input with a leading icon sitting inside the field. */
function IconInput({
  id,
  icon: Icon,
  value,
  onChange,
  placeholder,
  type = "text",
  autoComplete,
  invalid,
}: {
  id: string;
  icon: React.ComponentType<{ className?: string }>;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  type?: string;
  autoComplete?: string;
  invalid?: boolean;
}) {
  return (
    <div className="relative">
      <Icon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
      <Input
        id={id}
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        autoComplete={autoComplete}
        aria-invalid={invalid || undefined}
        aria-describedby={invalid ? `${id}-error` : undefined}
        className={cn("h-11 pl-9", invalid && "border-destructive")}
      />
    </div>
  );
}

/**
 * Phone field with a fixed +91 alongside it, so the player types only the
 * ten local digits. The stored value keeps the dial code, which is what the
 * validator and the server both see.
 */
function PhoneInput({
  id,
  value,
  onChange,
  placeholder,
  autoComplete,
  invalid,
}: {
  id: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  autoComplete?: string;
  invalid?: boolean;
}) {
  return (
    <div
      className={cn(
        "flex h-11 items-center overflow-hidden rounded-xl border border-input bg-transparent shadow-sm transition-colors focus-within:border-ring focus-within:ring-2 focus-within:ring-ring/40",
        invalid && "border-destructive",
      )}
    >
      <span className="flex h-full shrink-0 items-center gap-1.5 border-r border-input px-3 text-sm text-muted-foreground">
        <Phone className="h-4 w-4" aria-hidden />
        {DEFAULT_DIAL_CODE}
      </span>
      <input
        id={id}
        type="tel"
        inputMode="numeric"
        value={localPhonePart(value)}
        onChange={(e) => onChange(withDialCode(e.target.value))}
        placeholder={placeholder}
        autoComplete={autoComplete}
        aria-invalid={invalid || undefined}
        aria-describedby={invalid ? `${id}-error` : undefined}
        className="h-full min-w-0 flex-1 bg-transparent px-3 text-sm outline-none placeholder:text-muted-foreground"
      />
    </div>
  );
}

function ReviewStep({
  facility,
  sportName,
  summary,
  guest,
  error,
  agreed,
  onAgreedChange,
}: {
  facility: PublicBookingFacility;
  sportName: string;
  summary: PickSummary;
  guest: PublicGuestDetails;
  error: string | null;
  agreed: boolean;
  onAgreedChange: (v: boolean) => void;
}) {
  const cur = facility.currency;
  const first = summary.requests[0]!;

  return (
    <div className="space-y-5">
      {error && <Notice tone="error" title="We Couldn't Confirm That" message={error} />}

      <div className="grid gap-4 lg:grid-cols-3">
        <ReviewPanel title="Guest Information">
          <StackedRow label="Full Name" value={guest.fullName} />
          <StackedRow label="Mobile Number" value={guest.phone} />
          {guest.email.trim() && <StackedRow label="Email Address" value={guest.email} />}
          {guest.altPhone.trim() && <StackedRow label="Alternate Phone" value={guest.altPhone} />}
          {guest.purpose && <StackedRow label="Purpose of Booking" value={guest.purpose} />}
          {guest.specialRequest.trim() && (
            <StackedRow label="Special Request" value={guest.specialRequest} />
          )}
        </ReviewPanel>

        <ReviewPanel title="Booking Details">
          <IconRow icon={LayoutGrid} label="Sport" value={sportName} />
          <IconRow icon={MapPin} label="Facility" value={facility.facilityName} />
          <IconRow icon={CalendarDays} label="Date" value={formatBookingDate(first.startTime)} />
          <ul className="space-y-2 pt-1">
            {summary.requests.map((r) => (
              <li key={`${r.courtId}-${r.startTime}`} className="rounded-lg bg-muted/40 px-3 py-2 text-sm">
                <p className="font-medium">{r.courtName}</p>
                <p className="text-xs text-muted-foreground">
                  {formatSlotRange(r.startTime, r.endTime)} · {durationLabel(r.startTime, r.endTime)}
                </p>
              </li>
            ))}
          </ul>
        </ReviewPanel>

        <ReviewPanel title="Payment Details">
          {summary.advanceRequired ? (
            <div className="rounded-xl border border-primary/30 bg-primary/10 p-3">
              <p className="flex items-center gap-2 text-sm font-semibold">
                <WalletCards className="h-4 w-4 text-primary" aria-hidden />
                50% Advance Online
              </p>
              <p className="mt-0.5 text-xs text-muted-foreground">
                Bookings longer than 1 hour are held for 30 minutes and confirmed once the advance is paid online. The balance is paid at the venue.
              </p>
            </div>
          ) : (
            <div className="rounded-xl border border-primary/30 bg-primary/10 p-3">
              <p className="flex items-center gap-2 text-sm font-semibold">
                <WalletCards className="h-4 w-4 text-primary" aria-hidden />
                Payment at Venue
              </p>
              <p className="mt-0.5 text-xs text-muted-foreground">Please pay directly at the venue.</p>
            </div>
          )}

          <div className="pt-1">
            <p className="text-xs font-semibold">Price Details</p>
            <dl className="mt-2 space-y-2 text-sm">
              {summary.requests.map((r) => (
                <div key={`${r.courtId}-${r.startTime}`} className="flex items-baseline justify-between gap-3">
                  <dt className="text-muted-foreground">
                    {r.courtName} ({durationLabel(r.startTime, r.endTime)})
                  </dt>
                  <dd className="font-medium">{formatMoney(r.totalMinor, cur)}</dd>
                </div>
              ))}
              <div className="flex items-baseline justify-between gap-3 border-t border-border pt-2">
                <dt className="font-semibold text-primary">Total Amount</dt>
                <dd className="text-base font-semibold text-primary">{formatMoney(summary.totalMinor, cur)}</dd>
              </div>
              {summary.advanceRequired && (
                <>
                  <div className="flex items-baseline justify-between gap-3">
                    <dt className="font-semibold">Advance Due Online (50%)</dt>
                    <dd className="font-semibold">{formatMoney(summary.advanceDueMinor, cur)}</dd>
                  </div>
                  <div className="flex items-baseline justify-between gap-3">
                    <dt className="text-muted-foreground">Balance at Venue</dt>
                    <dd className="font-medium">{formatMoney(summary.balanceMinor, cur)}</dd>
                  </div>
                </>
              )}
            </dl>
          </div>
        </ReviewPanel>
      </div>

      {/* Consent is the last thing between the player and a real booking, so
          it sits with the details it refers to rather than in the footer. */}
      <label className="flex cursor-pointer items-start gap-2.5 rounded-xl border border-border p-3 text-sm">
        <input
          type="checkbox"
          checked={agreed}
          onChange={(e) => onAgreedChange(e.target.checked)}
          className="mt-0.5 h-4 w-4 shrink-0 accent-[var(--primary)]"
          aria-describedby="terms-help"
        />
        <span id="terms-help" className="text-muted-foreground">
          I agree to the <span className="font-medium text-primary">Terms and conditions</span> and confirm
          that the above details are correct.
        </span>
      </label>
    </div>
  );
}

/** One of the three review columns. */
function ReviewPanel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-border p-4">
      <h2 className="mb-3 text-sm font-semibold">{title}</h2>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

/** Label above value — for free text that would crowd a single line. */
function StackedRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[11px] text-muted-foreground">{label}</p>
      <p className="text-sm font-medium break-words">{value}</p>
    </div>
  );
}

/** Label left, value right with its icon — for short, scannable facts. */
function IconRow({
  icon: Icon,
  label,
  value,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: string;
}) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span className="flex min-w-0 items-center gap-1.5 text-sm font-medium">
        <Icon className="h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
        <span className="truncate">{value}</span>
      </span>
    </div>
  );
}

function SummaryPanel({
  open,
  onToggle,
  facility,
  sportName,
  summary,
}: {
  open: boolean;
  onToggle: () => void;
  facility: PublicBookingFacility;
  sportName: string;
  summary: PickSummary;
}) {
  const cur = facility.currency;
  const body = (
    <dl className="space-y-1.5 text-sm">
      <Row label="Sport" value={sportName} />
      <Row label="Date" value={formatBookingDate(summary.requests[0]!.startTime)} />
      {summary.requests.map((r) => (
        <Row key={`${r.courtId}-${r.startTime}`} label={r.courtName} value={`${formatSlotRange(r.startTime, r.endTime)} (${durationLabel(r.startTime, r.endTime)})`} />
      ))}
      <div className="flex items-center justify-between border-t border-border pt-2 font-semibold">
        <span>Total</span>
        <span>{formatMoney(summary.totalMinor, cur)}</span>
      </div>
      {summary.advanceRequired ? (
        <>
          <div className="flex items-center justify-between font-semibold">
            <span>Advance Online (50%)</span>
            <span>{formatMoney(summary.advanceDueMinor, cur)}</span>
          </div>
          <p className="pt-1 text-xs text-muted-foreground">Balance {formatMoney(summary.balanceMinor, cur)} at the venue</p>
        </>
      ) : (
        <p className="pt-1 text-xs text-muted-foreground">Pay at venue</p>
      )}
    </dl>
  );

  return (
    <>
      {/* Mobile: collapsible, so the summary never pushes the form off-screen. */}
      <section className="mt-6 rounded-xl border border-border lg:hidden">
        <button
          type="button"
          onClick={onToggle}
          aria-expanded={open}
          className="flex min-h-12 w-full items-center justify-between px-4 text-sm font-medium"
        >
          Booking summary
          <ChevronDown className={cn("h-4 w-4 transition-transform", open && "rotate-180")} aria-hidden />
        </button>
        {open && <div className="border-t border-border p-4">{body}</div>}
      </section>

      {/* Desktop: sticky beside the form. */}
      <aside className="sticky top-6 hidden rounded-xl border border-border p-4 lg:block">
        <h2 className="mb-3 text-sm font-medium">Booking Summary</h2>
        {body}
      </aside>
    </>
  );
}

/**
 * The bar that carries the running total and the forward action.
 *
 * Sticky at the bottom of the viewport on phones — the design's key point:
 * what you are about to pay, and the way onwards, stay in reach however far
 * down the slot list you have scrolled. On desktop it settles into the foot
 * of the booking card, where there is room for the full summary line.
 */
function BookingActionBar({
  step,
  facility,
  sportName,
  summary,
  submitting,
  agreed,
  onBack,
  onNext,
}: {
  step: Step;
  facility: PublicBookingFacility;
  sportName: string;
  summary: PickSummary | null;
  submitting: boolean;
  agreed: boolean;
  onBack: () => void;
  onNext: () => void;
}) {
  if (step === "done" || step === "pay") return null;

  // Step 1 needs a slot; the last step needs the player to have ticked the
  // consent box beside the details it refers to.
  const canContinue = step === "select" ? Boolean(summary) : step === "review" ? agreed : true;
  const advance = Boolean(summary?.advanceRequired);
  const label =
    step === "review"
      ? submitting
        ? "Confirming booking…"
        : advance
          ? "Confirm & Pay Advance"
          : "Confirm Booking"
      : step === "details"
        ? "Review & Confirm"
        : "Continue";

  // The total belongs beside the action while the player is choosing or
  // confirming. On the details step the desktop summary panel already
  // carries it, and the design keeps that footer to just the two buttons.
  const showTotal = step === "select";
  const cur = facility.currency;
  const courtsLabel = summary ? [...new Set(summary.requests.map((r) => r.courtName))].join(", ") : "";
  const timesLabel = summary ? summary.requests.map((r) => formatSlotRange(r.startTime, r.endTime)).join(", ") : "";

  return (
    <div className="sticky bottom-0 z-10 border-t border-border bg-card/95 px-4 py-3 backdrop-blur sm:px-8">
      <div className="flex items-center gap-3">
        <div className="min-w-0 flex-1">
          {summary ? (
            <>
              {/* The full context line has room only on larger screens; the
                  phone keeps the total, which is what a player checks. */}
              <p className="hidden truncate text-xs text-muted-foreground sm:block">
                {[sportName, facility.facilityName, courtsLabel].filter(Boolean).join(" • ")}
              </p>
              <p className="hidden truncate text-xs text-muted-foreground sm:block">
                {formatBookingDate(summary.requests[0]!.startTime)} • {timesLabel} • {summary.hours} {summary.hours === 1 ? "hour" : "hours"}
              </p>
              <p className="text-[11px] text-muted-foreground sm:hidden">{advance ? "Total · advance now" : "Total"}</p>
              <p className="text-base font-semibold text-primary sm:hidden">
                {formatMoney(summary.totalMinor, cur)}
                {advance && <span className="text-xs font-medium text-muted-foreground"> · {formatMoney(summary.advanceDueMinor, cur)} now</span>}
              </p>
            </>
          ) : (
            <p className="text-xs text-muted-foreground">Pick a court and time to continue.</p>
          )}
        </div>

        {summary && showTotal && (
          <div className="hidden text-right sm:block">
            <p className="text-[11px] text-muted-foreground">{advance ? `Total · ${formatMoney(summary.advanceDueMinor, cur)} advance now` : "Total"}</p>
            <p className="text-lg font-semibold text-primary">{formatMoney(summary.totalMinor, cur)}</p>
          </div>
        )}

        {step !== "select" && (
          <Button type="button" variant="outline" onClick={onBack} disabled={submitting} className="min-h-11 shrink-0">
            <ArrowLeft className="h-4 w-4" aria-hidden />
            <span className="hidden sm:inline">Back</span>
          </Button>
        )}

        <Button
          type="button"
          onClick={onNext}
          disabled={!canContinue || submitting}
          className="min-h-11 shrink-0"
        >
          {step === "review" && !submitting && <Lock className="h-4 w-4" aria-hidden />}
          {label}
          {step !== "review" && !submitting && <ArrowRight className="h-4 w-4" aria-hidden />}
        </Button>
      </div>

      {step === "select" && summary && (
        <p className="mt-1 hidden text-right text-[11px] text-muted-foreground sm:block">
          You can review your booking next
        </p>
      )}
    </div>
  );
}

const PAYMENT_STATUS_LABEL: Record<PublicBookingReceipt["paymentStatus"], string> = {
  PAID: "Fully Paid",
  PARTIALLY_PAID: "Partially Paid",
  PENDING: "Pay at Venue",
};

/** The booking as the confirmation page shows it: the server's receipt when it has arrived, else what we already know. */
function receiptFallback(c: PublicBookingConfirmation): PublicBookingReceipt {
  const paid = c.advanceRequired ? Math.min(c.advanceMinor ?? 0, c.amountMinor) : 0;
  return {
    found: true,
    bookingId: c.bookingId,
    code: c.code,
    confirmed: true,
    cancelled: false,
    holdExpiresAt: null,
    facilityName: c.facilityName,
    sportName: c.sportName,
    courtName: c.courtName,
    startTime: c.startTime,
    endTime: c.endTime,
    guestName: c.guestName,
    guestPhone: c.guestPhone,
    partySize: 1,
    currency: c.currency,
    amountMinor: c.amountMinor,
    paidMinor: paid,
    outstandingMinor: Math.max(c.amountMinor - paid, 0),
    paymentStatus: paid >= c.amountMinor && c.amountMinor > 0 ? "PAID" : paid > 0 ? "PARTIALLY_PAID" : "PENDING",
    paymentMethod: paid > 0 ? "Razorpay" : null,
    paymentReference: null,
    paidAt: null,
  };
}

function Confirmed({
  confirmations,
  facility,
  embedded,
  notice,
  phone,
}: {
  confirmations: PublicBookingConfirmation[];
  facility: PublicBookingFacility;
  embedded: boolean;
  notice?: string | null;
  phone: string;
}) {
  const confirmation = confirmations[0]!;
  const multiple = confirmations.length > 1;
  const [receipts, setReceipts] = useState<Record<string, PublicBookingReceipt>>({});
  const [invoiceBusy, setInvoiceBusy] = useState<string | null>(null);
  const [invoiceError, setInvoiceError] = useState<string | null>(null);

  // The booking's real payment position (what arrived, what is still owed) comes from the server.
  useEffect(() => {
    let active = true;
    for (const c of confirmations) {
      void getPublicBookingReceipt(c.bookingId, phone).then((r) => {
        if (active && r) setReceipts((cur) => ({ ...cur, [c.bookingId]: r }));
      });
    }
    return () => {
      active = false;
    };
  }, [confirmations, phone]);

  async function downloadInvoice(c: PublicBookingConfirmation) {
    setInvoiceError(null);
    setInvoiceBusy(c.bookingId);
    try {
      await downloadPublicBookingInvoice(c.bookingId, phone, `invoice-${c.code}.pdf`);
    } catch (e) {
      setInvoiceError(e instanceof Error ? e.message : "We couldn't build the invoice. Please try again.");
    } finally {
      setInvoiceBusy(null);
    }
  }

  const calendarHref = useMemo(() => {
    const stamp = (iso: string) => new Date(iso).toISOString().replace(/[-:]|\.\d{3}/g, "");
    const params = new URLSearchParams({
      action: "TEMPLATE",
      text: `${confirmation.sportName} at ${confirmation.facilityName}`,
      dates: `${stamp(confirmation.startTime)}/${stamp(confirmation.endTime)}`,
      details: `Booking ${confirmation.code} — ${confirmation.courtName}.`,
      location: confirmation.facilityName,
    });
    return `https://calendar.google.com/calendar/render?${params.toString()}`;
  }, [confirmation]);

  const [shared, setShared] = useState(false);

  async function share() {
    const text = confirmations
      .map((c) => `Booking ${c.code} — ${c.sportName} at ${c.facilityName}, ${c.courtName}, ${formatBookingDate(c.startTime)} ${formatSlotRange(c.startTime, c.endTime)}`)
      .join("\n");
    if (navigator.share) {
      try {
        await navigator.share({ title: "Booking Confirmed", text });
        return;
      } catch {
        // Cancelled, or the sheet is unavailable — fall through to copying.
      }
    }
    try {
      await navigator.clipboard?.writeText(text);
      setShared(true);
      setTimeout(() => setShared(false), 2000);
    } catch {
      // Nothing sensible left to try; the details are on screen to copy.
    }
  }

  return (
    <div className={cn("mx-auto w-full max-w-5xl px-4", embedded ? "py-4" : "py-6 sm:py-10")}>
      <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
        {!embedded && (
          <PublicBookingHeader
            helpPhone={facility.helpPhone}
            facilityName={facility.facilityName}
            city={facility.city}
          />
        )}

        <div className="px-4 py-8 sm:px-8 sm:py-10">
          <div className="text-center">
            <SuccessBadge />
            <h1 className="mt-4 text-xl font-bold tracking-tight sm:text-2xl">
              {multiple ? "Bookings Confirmed!" : "Booking Confirmed!"}
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {multiple ? "Your courts have been successfully booked." : "Your court has been successfully booked."}
            </p>
          </div>

          {notice && <Notice tone="error" title="Some Bookings Weren't Made" message={notice} className="mx-auto mt-6 max-w-3xl" />}
          {invoiceError && <Notice tone="error" title="Invoice" message={invoiceError} className="mx-auto mt-6 max-w-3xl" />}

          <div className="mx-auto mt-6 max-w-3xl space-y-4">
            {confirmations.map((c) => {
              const r = receipts[c.bookingId] ?? receiptFallback(c);
              const cur = r.currency;
              return (
                <section key={c.bookingId} className="overflow-hidden rounded-xl border border-border">
                  <dl className="grid gap-px bg-border sm:grid-cols-3">
                    <ConfirmedCell label="Booking ID">
                      <span className="text-base font-bold text-primary">{r.code}</span>
                    </ConfirmedCell>
                    <ConfirmedCell label="Booked By" icon={UserRound}>
                      {r.guestName}
                      {r.guestPhone ? <span className="block text-xs font-normal text-muted-foreground">{r.guestPhone}</span> : null}
                    </ConfirmedCell>
                    <ConfirmedCell label="Sport" icon={LayoutGrid}>
                      {r.sportName}
                    </ConfirmedCell>

                    <ConfirmedCell label="Court / Turf" icon={MapPin}>
                      {r.courtName}
                    </ConfirmedCell>
                    <ConfirmedCell label="Date" icon={CalendarDays}>
                      {formatBookingDate(r.startTime)}
                    </ConfirmedCell>
                    <ConfirmedCell label="Time">
                      {formatSlotRange(r.startTime, r.endTime)}
                      <span className="block text-xs font-normal text-muted-foreground">{durationLabel(r.startTime, r.endTime)}</span>
                    </ConfirmedCell>
                  </dl>

                  <div className="space-y-2 border-t border-border bg-card p-4 text-sm">
                    <div className="flex items-center justify-between">
                      <span className="flex items-center gap-2 text-xs text-muted-foreground">
                        <WalletCards className="h-4 w-4" aria-hidden /> Payment Status
                      </span>
                      <span
                        className={cn(
                          "rounded-full px-2.5 py-0.5 text-xs font-semibold",
                          r.paymentStatus === "PAID" && "bg-primary/15 text-primary",
                          r.paymentStatus === "PARTIALLY_PAID" && "bg-amber-500/15 text-amber-600",
                          r.paymentStatus === "PENDING" && "bg-muted text-muted-foreground",
                        )}
                      >
                        {PAYMENT_STATUS_LABEL[r.paymentStatus]}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-muted-foreground">Total Amount</span>
                      <span className="font-semibold">{formatMoney(r.amountMinor, cur)}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-muted-foreground">Paid Amount</span>
                      <span className="font-semibold text-primary">{formatMoney(r.paidMinor, cur)}</span>
                    </div>
                    {r.outstandingMinor > 0 && (
                      <div className="flex items-center justify-between">
                        <span className="text-muted-foreground">Pending Amount (pay at the venue)</span>
                        <span className="font-semibold">{formatMoney(r.outstandingMinor, cur)}</span>
                      </div>
                    )}
                    {r.paidMinor > 0 && (r.paymentMethod || r.paymentReference) && (
                      <div className="flex items-center justify-between text-xs text-muted-foreground">
                        <span>Paid via {r.paymentMethod ?? "Razorpay"}</span>
                        {r.paymentReference && <span className="tabular-nums">Ref {r.paymentReference}</span>}
                      </div>
                    )}
                  </div>

                  <div className="border-t border-border bg-muted/30 p-3">
                    <Button
                      type="button"
                      variant="outline"
                      className="min-h-10 w-full sm:w-auto"
                      disabled={invoiceBusy === c.bookingId}
                      onClick={() => void downloadInvoice(c)}
                    >
                      <Download className="h-4 w-4" aria-hidden />
                      {invoiceBusy === c.bookingId ? "Preparing invoice…" : "Download Invoice"}
                    </Button>
                  </div>
                </section>
              );
            })}
          </div>

          <div className="mx-auto mt-6 grid max-w-3xl gap-2 sm:grid-cols-3">
            <Button asChild variant="outline" className="min-h-11">
              <a href={calendarHref} target="_blank" rel="noopener noreferrer">
                Add to Calendar <CalendarDays className="h-4 w-4" aria-hidden />
              </a>
            </Button>
            <Button type="button" variant="outline" onClick={share} className="min-h-11">
              {shared ? "Copied" : "Share Booking"}
              <Share2 className="h-4 w-4" aria-hidden />
            </Button>
            <Button asChild className="min-h-11">
              <Link href={`/book/${facility.facilityId}`}>Back to Home</Link>
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}

/** One held booking waiting on its advance. */
interface PendingItem {
  confirmation: PublicBookingConfirmation;
  state: "waiting" | "confirmed" | "expired";
}

/** mm:ss until the hold lapses. */
function HoldCountdown({ until }: { until: string }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);
  const left = Math.max(0, Math.floor((new Date(until).getTime() - now) / 1000));
  return (
    <span className="tabular-nums">
      {String(Math.floor(left / 60)).padStart(2, "0")}:{String(left % 60).padStart(2, "0")}
    </span>
  );
}

/**
 * The Payment step for a booking longer than an hour. The court is held for 30 minutes; "Proceed to Pay" opens
 * Razorpay Checkout for the 50% advance (no link is made or shared), and the booking is confirmed once the payment
 * is verified. However many courts and times were booked, it is ONE payment for the whole advance.
 */
function PayStep({
  items,
  payingId,
  error,
  notice,
  onPay,
  onBookAgain,
}: {
  items: PendingItem[];
  payingId: string | null;
  error: string | null;
  notice: string | null;
  onPay: () => void;
  onBookAgain: () => void;
}) {
  const waiting = items.filter((i) => i.state === "waiting");
  const allExpired = items.length > 0 && items.every((i) => i.state === "expired");
  const cur = items[0]?.confirmation.currency ?? "INR";
  const total = items.filter((i) => i.state !== "expired").reduce((s, i) => s + i.confirmation.amountMinor, 0);
  const dueNow = waiting.reduce((s, i) => s + (i.confirmation.advanceMinor ?? 0), 0);
  const paidSoFar = items.filter((i) => i.state === "confirmed").reduce((s, i) => s + (i.confirmation.advanceMinor ?? 0), 0);
  const paying = payingId !== null;

  return (
    <div className="space-y-5">
      <div>
        <h2 className="text-base font-semibold">Pay Your Advance</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Your court is held while you pay. Bookings longer than 1 hour are confirmed once 50% is paid online — the balance is paid at the venue.
        </p>
      </div>

      {notice && <Notice tone="error" title="Some Bookings Weren't Made" message={notice} />}
      {error && <Notice tone="error" title="Payment Not Completed" message={error} />}

      <ul className="space-y-3">
        {items.map((item) => {
          const c = item.confirmation;
          return (
            <li key={c.bookingId} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border p-4">
              <div className="min-w-0">
                <p className="text-sm font-semibold">{c.courtName}</p>
                <p className="text-xs text-muted-foreground">
                  {formatBookingDate(c.startTime)} · {formatSlotRange(c.startTime, c.endTime)} · {durationLabel(c.startTime, c.endTime)}
                </p>
              </div>
              <div className="text-right text-xs">
                {item.state === "confirmed" ? (
                  <span className="flex items-center gap-1.5 text-sm font-medium text-primary">
                    <CircleCheck className="h-4 w-4" aria-hidden /> Advance paid
                  </span>
                ) : item.state === "expired" ? (
                  <span className="text-sm font-medium text-destructive">Expired — the court was released</span>
                ) : (
                  <>
                    <p className="text-sm font-semibold">{formatMoney(c.advanceMinor ?? 0, c.currency)} advance</p>
                    {c.holdExpiresAt && (
                      <p className="text-muted-foreground">
                        Held for <HoldCountdown until={c.holdExpiresAt} />
                      </p>
                    )}
                  </>
                )}
              </div>
            </li>
          );
        })}
      </ul>

      {!allExpired && (
        <dl className="space-y-2 rounded-xl border border-border p-4 text-sm">
          <div className="flex justify-between">
            <dt className="text-muted-foreground">Total Amount</dt>
            <dd className="font-medium">{formatMoney(total, cur)}</dd>
          </div>
          {paidSoFar > 0 && (
            <div className="flex justify-between">
              <dt className="text-muted-foreground">Already Paid</dt>
              <dd className="font-medium text-primary">{formatMoney(paidSoFar, cur)}</dd>
            </div>
          )}
          <div className="flex justify-between border-t border-border pt-2">
            <dt className="font-semibold">Advance to Pay Now (50%)</dt>
            <dd className="text-base font-semibold text-primary">{formatMoney(dueNow, cur)}</dd>
          </div>
          <div className="flex justify-between">
            <dt className="text-muted-foreground">Balance at the Venue</dt>
            <dd className="font-medium">{formatMoney(Math.max(total - paidSoFar - dueNow, 0), cur)}</dd>
          </div>
        </dl>
      )}

      {allExpired ? (
        <Button type="button" onClick={onBookAgain} className="min-h-11">
          Book Again
        </Button>
      ) : (
        <div className="space-y-2">
          {/* One payment covers every held booking, however many courts and times were picked. */}
          <Button type="button" onClick={onPay} disabled={paying || waiting.length === 0} className="min-h-11 w-full sm:w-auto">
            <Lock className="h-4 w-4" aria-hidden />
            {paying ? "Opening Razorpay…" : `Proceed to Pay ${formatMoney(dueNow, cur)}`}
          </Button>
          <p className="text-xs text-muted-foreground">You&apos;ll pay securely with Razorpay — UPI, cards, net banking and wallets.</p>
        </div>
      )}
    </div>
  );
}

/** The tick, with a scatter of confetti behind it. */
function SuccessBadge() {
  // Fixed positions rather than random, so the mark renders identically on
  // the server and the client and never animates on a page people screenshot.
  const confetti = [
    { x: "12%", y: "18%", c: "bg-primary" },
    { x: "26%", y: "6%", c: "bg-amber-400" },
    { x: "44%", y: "0%", c: "bg-primary" },
    { x: "68%", y: "8%", c: "bg-sky-400" },
    { x: "84%", y: "22%", c: "bg-amber-400" },
    { x: "6%", y: "52%", c: "bg-sky-400" },
    { x: "92%", y: "56%", c: "bg-primary" },
  ];

  return (
    <div className="relative mx-auto h-20 w-40">
      {confetti.map((d) => (
        <span
          key={`${d.x}-${d.y}`}
          className={cn("absolute h-1.5 w-1.5 rounded-full opacity-70", d.c)}
          style={{ left: d.x, top: d.y }}
          aria-hidden
        />
      ))}
      <span className="absolute left-1/2 top-1/2 flex h-14 w-14 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-primary text-primary-foreground">
        <Check className="h-7 w-7" aria-hidden strokeWidth={3} />
      </span>
    </div>
  );
}

function ConfirmedCell({
  label,
  icon: Icon,
  children,
}: {
  label: string;
  icon?: React.ComponentType<{ className?: string }>;
  children: React.ReactNode;
}) {
  return (
    <div className="bg-card p-4">
      <dt className="text-[11px] text-muted-foreground">{label}</dt>
      <dd className="mt-1 flex items-center gap-1.5 text-sm font-medium">
        {Icon && <Icon className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />}
        <span className="truncate">{children}</span>
      </dd>
    </div>
  );
}

function Field({
  id,
  label,
  required,
  hint,
  error,
  icon: Icon,
  children,
}: {
  id: string;
  label: string;
  required?: boolean;
  hint?: string;
  error?: string;
  icon?: React.ComponentType<{ className?: string }>;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id} className="flex items-center gap-1 text-xs font-medium">
        {Icon && <Icon className="h-3.5 w-3.5 text-muted-foreground" aria-hidden />}
        {label}
        {required && (
          <span className="text-destructive" aria-hidden>
            *
          </span>
        )}
        {hint && <span className="font-normal text-muted-foreground">({hint})</span>}
      </Label>
      {children}
      {error && (
        <p id={`${id}-error`} role="alert" className="flex items-center gap-1 text-xs text-destructive">
          <CircleAlert className="h-3.5 w-3.5 shrink-0" aria-hidden />
          {error}
        </p>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-right font-medium">{value}</dd>
    </div>
  );
}

function Notice({
  tone,
  title,
  message,
  className,
}: {
  tone: "error" | "info";
  title: string;
  message: string;
  className?: string;
}) {
  return (
    <div
      role="alert"
      className={cn(
        "rounded-xl border p-4",
        tone === "error" ? "border-destructive/40 bg-destructive/5" : "border-border",
        className,
      )}
    >
      <p className="flex items-center gap-2 text-sm font-medium">
        <CircleAlert className="h-4 w-4 shrink-0 text-destructive" aria-hidden />
        {title}
      </p>
      <p className="mt-1 text-sm text-muted-foreground">{message}</p>
    </div>
  );
}

function FlowSkeleton() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-10" aria-busy>
      <Skeleton className="h-7 w-48" />
      <Skeleton className="mt-2 h-4 w-64" />
      <div className="mt-8 space-y-4">
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-20 w-full" />
        <Skeleton className="h-40 w-full" />
      </div>
    </div>
  );
}
