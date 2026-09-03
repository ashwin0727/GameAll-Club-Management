"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  CalendarDays,
  ChevronDown,
  CircleAlert,
  CircleCheck,
  LayoutGrid,
  Mail,
  MapPin,
  Phone,
  UserRound,
  WalletCards,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { APP_NAME } from "@/lib/constants";
import {
  SlotUnavailableError,
  createPublicGuestBooking,
  getPublicBookingFacility,
  getPublicCourtAvailability,
} from "../public-booking";
import {
  EMPTY_GUEST,
  durationLabel,
  formatBookingDate,
  formatMoney,
  formatSlotRange,
  toDateParam,
  validateGuest,
  type GuestFieldErrors,
} from "../guest-form";
import { BOOKING_PURPOSES, type PublicBookingConfirmation, type PublicBookingCourt, type PublicBookingFacility, type PublicGuestDetails } from "../types";

type Step = "select" | "details" | "review" | "done";

const STEPS: { id: Step; label: string }[] = [
  { id: "select", label: "Court & Time" },
  { id: "details", label: "Your Details" },
  { id: "review", label: "Review" },
];

interface Selection {
  courtId: string;
  courtName: string;
  startTime: string;
  endTime: string;
  priceMinor: number;
}

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

  const [selection, setSelection] = useState<Selection | null>(null);
  const [guest, setGuest] = useState<PublicGuestDetails>(EMPTY_GUEST);
  const [errors, setErrors] = useState<GuestFieldErrors>({});

  const [step, setStep] = useState<Step>("select");
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [confirmation, setConfirmation] = useState<PublicBookingConfirmation | null>(null);
  const [summaryOpen, setSummaryOpen] = useState(false);

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

  const loadSlots = useCallback(async () => {
    if (!sportId) return;
    setSlotsLoading(true);
    try {
      setCourts(await getPublicCourtAvailability(facilityId, sportId, toDateParam(date)));
    } finally {
      setSlotsLoading(false);
    }
  }, [facilityId, sportId, date]);

  useEffect(() => {
    void loadSlots();
    // Changing sport or date invalidates any slot already picked.
    setSelection(null);
  }, [loadSlots]);

  const sportName = facility?.sports.find((s) => s.facilitySportId === sportId)?.name ?? "";

  function goToDetails() {
    if (!selection) return;
    setFormError(null);
    setStep("details");
  }

  function goToReview() {
    const found = validateGuest(guest);
    setErrors(found);
    if (Object.keys(found).length > 0) return;
    setFormError(null);
    setStep("review");
  }

  /** Send the player back to slot selection after losing a race for a slot. */
  function returnToSelection(message: string) {
    setSelection(null);
    setStep("select");
    setFormError(message);
    void loadSlots();
  }

  async function confirm() {
    if (!selection || submitting) return;
    setSubmitting(true);
    setFormError(null);
    try {
      const result = await createPublicGuestBooking({
        facilityId,
        courtId: selection.courtId,
        startTime: selection.startTime,
        endTime: selection.endTime,
        guest,
      });
      setConfirmation(result);
      setStep("done");
    } catch (e) {
      if (e instanceof SlotUnavailableError) {
        returnToSelection("Sorry, this court is no longer available. Please choose another time.");
      } else {
        setFormError(e instanceof Error ? e.message : "Something went wrong. Please try again.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  if (facilityLoading) return <FlowSkeleton />;

  if (!facility) {
    return (
      <Notice
        tone="error"
        title="We couldn't find this venue"
        message="The booking link may be incorrect or no longer active."
      />
    );
  }

  if (facility.sports.length === 0) {
    return (
      <Notice
        tone="error"
        title="No courts available"
        message="This venue isn't accepting online bookings right now."
      />
    );
  }

  if (step === "done" && confirmation) {
    return <Confirmed confirmation={confirmation} />;
  }

  return (
    <div className={cn("mx-auto w-full max-w-5xl px-4", embedded ? "py-4" : "py-6 sm:py-10")}>
      <header className="mb-6">
        <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">Book Your Court</h1>
        <p className="mt-1 flex items-center gap-1.5 text-sm text-muted-foreground">
          <MapPin className="h-4 w-4 shrink-0" aria-hidden />
          <span>
            {facility.facilityName}
            {facility.city ? `, ${facility.city}` : ""}
          </span>
        </p>
      </header>

      <StepBar current={step} />

      <div className="mt-6 gap-6 lg:grid lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start">
        <div className="min-w-0">
          {formError && step === "select" && (
            <Notice tone="error" title="That slot just went" message={formError} className="mb-4" />
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
              selection={selection}
              onSelect={setSelection}
              currency={facility.currency}
            />
          )}

          {step === "details" && (
            <DetailsStep guest={guest} errors={errors} onChange={setGuest} />
          )}

          {step === "review" && selection && (
            <ReviewStep
              facility={facility}
              sportName={sportName}
              selection={selection}
              guest={guest}
              error={formError}
            />
          )}
        </div>

        {selection && step !== "done" && (
          <SummaryPanel
            open={summaryOpen}
            onToggle={() => setSummaryOpen((v) => !v)}
            facility={facility}
            sportName={sportName}
            selection={selection}
          />
        )}
      </div>

      <StepActions
        step={step}
        canContinue={step === "select" ? Boolean(selection) : true}
        submitting={submitting}
        onBack={() => {
          setFormError(null);
          setStep(step === "review" ? "details" : "select");
        }}
        onNext={step === "select" ? goToDetails : step === "details" ? goToReview : confirm}
      />
    </div>
  );
}

function StepBar({ current }: { current: Step }) {
  const index = STEPS.findIndex((s) => s.id === current);
  return (
    <ol className="flex items-center gap-2" aria-label="Booking steps">
      {STEPS.map((s, i) => {
        const done = i < index;
        const active = i === index;
        return (
          <li key={s.id} className="flex flex-1 items-center gap-2">
            <span
              className={cn(
                "flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
                active && "bg-primary text-primary-foreground",
                done && "bg-primary/20 text-primary",
                !active && !done && "bg-muted text-muted-foreground",
              )}
              aria-current={active ? "step" : undefined}
            >
              {done ? <CircleCheck className="h-4 w-4" aria-hidden /> : i + 1}
            </span>
            <span className={cn("truncate text-xs", active ? "font-medium text-foreground" : "text-muted-foreground")}>
              {s.label}
            </span>
            {i < STEPS.length - 1 && <span className="hidden h-px flex-1 bg-border sm:block" aria-hidden />}
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
  selection,
  onSelect,
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
  selection: Selection | null;
  onSelect: (s: Selection) => void;
  currency: string;
}) {
  return (
    <div className="space-y-6">
      <section>
        <h2 className="mb-2 text-sm font-medium">Sport</h2>
        <div className="flex flex-wrap gap-2">
          {facility.sports.map((s) => (
            <button
              key={s.facilitySportId}
              type="button"
              onClick={() => onSportChange(s.facilitySportId)}
              aria-pressed={s.facilitySportId === sportId}
              className={cn(
                "min-h-11 rounded-full border px-4 text-sm transition-colors",
                s.facilitySportId === sportId
                  ? "border-primary bg-primary/10 font-medium text-foreground"
                  : "border-border hover:border-primary/40",
              )}
            >
              {s.name}
            </button>
          ))}
        </div>
      </section>

      <section>
        <h2 className="mb-2 flex items-center gap-1.5 text-sm font-medium">
          <CalendarDays className="h-4 w-4" aria-hidden /> Date
        </h2>
        <div className="-mx-4 flex snap-x gap-2 overflow-x-auto px-4 pb-1">
          {dates.map((d) => {
            const active = toDateParam(d) === toDateParam(date);
            return (
              <button
                key={d.toISOString()}
                type="button"
                onClick={() => onDateChange(d)}
                aria-pressed={active}
                className={cn(
                  "flex min-h-16 w-14 shrink-0 snap-start flex-col items-center justify-center rounded-xl border text-sm transition-colors",
                  active ? "border-primary bg-primary/10 font-medium" : "border-border hover:border-primary/40",
                )}
              >
                <span className="text-[11px] text-muted-foreground">
                  {d.toLocaleDateString("en-IN", { weekday: "short" })}
                </span>
                <span className="text-base">{d.getDate()}</span>
                <span className="text-[11px] text-muted-foreground">
                  {d.toLocaleDateString("en-IN", { month: "short" })}
                </span>
              </button>
            );
          })}
        </div>
      </section>

      <section>
        <h2 className="mb-2 flex items-center gap-1.5 text-sm font-medium">
          <LayoutGrid className="h-4 w-4" aria-hidden /> Court &amp; time
        </h2>

        {loading ? (
          <div className="space-y-4" aria-busy>
            {[0, 1].map((i) => (
              <div key={i} className="space-y-2">
                <Skeleton className="h-4 w-24" />
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                  {[0, 1, 2, 3, 4, 5].map((j) => (
                    <Skeleton key={j} className="h-14" />
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : courts.length === 0 ? (
          <p className="rounded-lg border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
            No courts are open on this date. Try another day.
          </p>
        ) : (
          <div className="space-y-5">
            {courts.map((court) => (
              <div key={court.courtId}>
                <h3 className="mb-2 text-sm font-medium text-muted-foreground">{court.courtName}</h3>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                  {court.slots.map((slot) => {
                    const active =
                      selection?.courtId === court.courtId && selection.startTime === slot.startTime;
                    return (
                      <button
                        key={slot.startTime}
                        type="button"
                        disabled={!slot.available}
                        aria-pressed={active}
                        onClick={() =>
                          onSelect({
                            courtId: court.courtId,
                            courtName: court.courtName,
                            startTime: slot.startTime,
                            endTime: slot.endTime,
                            priceMinor: slot.priceMinor,
                          })
                        }
                        className={cn(
                          "min-h-14 rounded-xl border px-2 py-2 text-left transition-colors",
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
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function DetailsStep({
  guest,
  errors,
  onChange,
}: {
  guest: PublicGuestDetails;
  errors: GuestFieldErrors;
  onChange: (g: PublicGuestDetails) => void;
}) {
  const set = (key: keyof PublicGuestDetails) => (value: string) => onChange({ ...guest, [key]: value });

  return (
    <div className="space-y-5">
      <Field id="fullName" label="Full name" required error={errors.fullName} icon={UserRound}>
        <Input
          id="fullName"
          value={guest.fullName}
          onChange={(e) => set("fullName")(e.target.value)}
          autoComplete="name"
          aria-invalid={Boolean(errors.fullName)}
          aria-describedby={errors.fullName ? "fullName-error" : undefined}
        />
      </Field>

      <Field id="phone" label="Mobile number" required error={errors.phone} icon={Phone}>
        <Input
          id="phone"
          type="tel"
          inputMode="tel"
          value={guest.phone}
          onChange={(e) => set("phone")(e.target.value)}
          autoComplete="tel"
          placeholder="+91 98765 43210"
          aria-invalid={Boolean(errors.phone)}
          aria-describedby={errors.phone ? "phone-error" : undefined}
        />
      </Field>

      <Field id="email" label="Email address" error={errors.email} icon={Mail} hint="Optional">
        <Input
          id="email"
          type="email"
          value={guest.email}
          onChange={(e) => set("email")(e.target.value)}
          autoComplete="email"
          aria-invalid={Boolean(errors.email)}
          aria-describedby={errors.email ? "email-error" : undefined}
        />
      </Field>

      <Field id="altPhone" label="Alternate phone" error={errors.altPhone} hint="Optional">
        <Input
          id="altPhone"
          type="tel"
          inputMode="tel"
          value={guest.altPhone}
          onChange={(e) => set("altPhone")(e.target.value)}
          aria-invalid={Boolean(errors.altPhone)}
          aria-describedby={errors.altPhone ? "altPhone-error" : undefined}
        />
      </Field>

      <Field id="address" label="Address" hint="Optional">
        <Input id="address" value={guest.address} onChange={(e) => set("address")(e.target.value)} />
      </Field>

      <fieldset>
        <legend className="mb-2 text-sm font-medium">
          Purpose of booking <span className="font-normal text-muted-foreground">(optional)</span>
        </legend>
        <div className="flex flex-wrap gap-2">
          {BOOKING_PURPOSES.map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => set("purpose")(guest.purpose === p ? "" : p)}
              aria-pressed={guest.purpose === p}
              className={cn(
                "min-h-11 rounded-full border px-4 text-sm transition-colors",
                guest.purpose === p
                  ? "border-primary bg-primary/10 font-medium"
                  : "border-border hover:border-primary/40",
              )}
            >
              {p}
            </button>
          ))}
        </div>
      </fieldset>

      <Field id="specialRequest" label="Special request" hint="Optional">
        <Textarea
          id="specialRequest"
          rows={3}
          value={guest.specialRequest}
          onChange={(e) => set("specialRequest")(e.target.value)}
        />
      </Field>
    </div>
  );
}

function ReviewStep({
  facility,
  sportName,
  selection,
  guest,
  error,
}: {
  facility: PublicBookingFacility;
  sportName: string;
  selection: Selection;
  guest: PublicGuestDetails;
  error: string | null;
}) {
  return (
    <div className="space-y-5">
      {error && <Notice tone="error" title="We couldn't confirm that" message={error} />}

      <Panel title="Your details">
        <Row label="Full name" value={guest.fullName} />
        <Row label="Mobile" value={guest.phone} />
        {guest.email.trim() && <Row label="Email" value={guest.email} />}
      </Panel>

      <Panel title="Booking details">
        <Row label="Sport" value={sportName} />
        <Row label="Venue" value={facility.facilityName} />
        <Row label="Court" value={selection.courtName} />
        <Row label="Date" value={formatBookingDate(selection.startTime)} />
        <Row label="Time" value={formatSlotRange(selection.startTime, selection.endTime)} />
        <Row label="Duration" value={durationLabel(selection.startTime, selection.endTime)} />
      </Panel>

      <Panel title="Price">
        <Row label="Court price" value={formatMoney(selection.priceMinor, facility.currency)} />
        <div className="mt-2 flex items-center justify-between border-t border-border pt-2 text-sm font-semibold">
          <span>Total</span>
          <span>{formatMoney(selection.priceMinor, facility.currency)}</span>
        </div>
      </Panel>

      <div className="rounded-xl border border-border bg-muted/40 p-4">
        <p className="flex items-center gap-2 text-sm font-medium">
          <WalletCards className="h-4 w-4 text-primary" aria-hidden /> Payment at venue
        </p>
        <p className="mt-1 text-sm text-muted-foreground">Payment will be collected at the venue.</p>
      </div>
    </div>
  );
}

function SummaryPanel({
  open,
  onToggle,
  facility,
  sportName,
  selection,
}: {
  open: boolean;
  onToggle: () => void;
  facility: PublicBookingFacility;
  sportName: string;
  selection: Selection;
}) {
  const body = (
    <dl className="space-y-1.5 text-sm">
      <Row label="Sport" value={sportName} />
      <Row label="Court" value={selection.courtName} />
      <Row label="Date" value={formatBookingDate(selection.startTime)} />
      <Row label="Time" value={formatSlotRange(selection.startTime, selection.endTime)} />
      <Row label="Duration" value={durationLabel(selection.startTime, selection.endTime)} />
      <div className="flex items-center justify-between border-t border-border pt-2 font-semibold">
        <span>Total</span>
        <span>{formatMoney(selection.priceMinor, facility.currency)}</span>
      </div>
      <p className="pt-1 text-xs text-muted-foreground">Pay at venue</p>
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
        <h2 className="mb-3 text-sm font-medium">Booking summary</h2>
        {body}
      </aside>
    </>
  );
}

function StepActions({
  step,
  canContinue,
  submitting,
  onBack,
  onNext,
}: {
  step: Step;
  canContinue: boolean;
  submitting: boolean;
  onBack: () => void;
  onNext: () => void;
}) {
  if (step === "done") return null;

  return (
    <div className="sticky bottom-0 z-10 -mx-4 mt-6 flex items-center gap-3 border-t border-border bg-background/95 px-4 py-3 backdrop-blur sm:static sm:mx-0 sm:border-0 sm:bg-transparent sm:px-0 sm:backdrop-blur-none">
      {step !== "select" && (
        <Button type="button" variant="outline" onClick={onBack} disabled={submitting} className="min-h-11">
          <ArrowLeft className="h-4 w-4" aria-hidden /> Back
        </Button>
      )}
      <Button
        type="button"
        onClick={onNext}
        disabled={!canContinue || submitting}
        className="min-h-11 flex-1 sm:flex-none"
      >
        {step === "review" ? (submitting ? "Confirming booking…" : "Confirm booking") : "Continue"}
        {!submitting && <ArrowRight className="h-4 w-4" aria-hidden />}
      </Button>
    </div>
  );
}

function Confirmed({ confirmation }: { confirmation: PublicBookingConfirmation }) {
  const calendarHref = useMemo(() => {
    const stamp = (iso: string) => new Date(iso).toISOString().replace(/[-:]|\.\d{3}/g, "");
    const params = new URLSearchParams({
      action: "TEMPLATE",
      text: `${confirmation.sportName} at ${confirmation.facilityName}`,
      dates: `${stamp(confirmation.startTime)}/${stamp(confirmation.endTime)}`,
      details: `Booking ${confirmation.code} — ${confirmation.courtName}. Pay at venue.`,
      location: confirmation.facilityName,
    });
    return `https://calendar.google.com/calendar/render?${params.toString()}`;
  }, [confirmation]);

  async function share() {
    const text = `Booking ${confirmation.code} — ${confirmation.sportName} at ${confirmation.facilityName}, ${confirmation.courtName}, ${formatBookingDate(confirmation.startTime)} ${formatSlotRange(confirmation.startTime, confirmation.endTime)}`;
    if (navigator.share) {
      try {
        await navigator.share({ title: "Booking confirmed", text });
        return;
      } catch {
        // Cancelled or unavailable — fall through to the clipboard.
      }
    }
    await navigator.clipboard?.writeText(text);
  }

  return (
    <div className="mx-auto w-full max-w-lg px-4 py-10">
      <div className="rounded-2xl border border-border p-6 text-center">
        <span className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-primary/15">
          <CircleCheck className="h-7 w-7 text-primary" aria-hidden />
        </span>
        <h1 className="mt-4 text-xl font-semibold">Booking confirmed</h1>
        <p className="mt-1 text-sm text-muted-foreground">Your court has been successfully booked.</p>

        <dl className="mt-6 space-y-2 text-left text-sm">
          <Row label="Booking ID" value={confirmation.code} />
          <Row label="Sport" value={confirmation.sportName} />
          <Row label="Venue" value={confirmation.facilityName} />
          <Row label="Court" value={confirmation.courtName} />
          <Row label="Date" value={formatBookingDate(confirmation.startTime)} />
          <Row label="Time" value={formatSlotRange(confirmation.startTime, confirmation.endTime)} />
          <Row label="Amount" value={formatMoney(confirmation.amountMinor, confirmation.currency)} />
          <Row label="Payment" value="Pay at venue" />
        </dl>

        <p className="mt-4 rounded-lg bg-muted/60 p-3 text-sm text-muted-foreground">
          Please complete payment at the venue.
        </p>

        <div className="mt-6 grid gap-2 sm:grid-cols-2">
          <Button asChild variant="outline" className="min-h-11">
            <a href={calendarHref} target="_blank" rel="noopener noreferrer">
              <CalendarDays className="h-4 w-4" aria-hidden /> Add to calendar
            </a>
          </Button>
          <Button type="button" variant="outline" onClick={share} className="min-h-11">
            Share booking
          </Button>
        </div>
      </div>
      <p className="mt-4 text-center text-xs text-muted-foreground">Powered by {APP_NAME}</p>
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
      <Label htmlFor={id} className="flex items-center gap-1.5">
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

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-border p-4">
      <h2 className="mb-2 text-sm font-medium">{title}</h2>
      <dl className="space-y-1.5 text-sm">{children}</dl>
    </section>
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
