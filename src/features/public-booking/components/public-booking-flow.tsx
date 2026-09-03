"use client";

import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  CalendarDays,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
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
import { PublicBookingHeader } from "./public-booking-header";
import { resolveFacilityHeroImage, type HeroImage } from "../hero-image";
import { BOOKING_PURPOSES, type PublicBookingConfirmation, type PublicBookingCourt, type PublicBookingFacility, type PublicGuestDetails } from "../types";

type Step = "select" | "details" | "review" | "done";

const STEPS: { id: Step; label: string }[] = [
  { id: "select", label: "Choose Court & Time" },
  { id: "details", label: "Guest Details" },
  { id: "review", label: "Review & Confirm" },
  { id: "done", label: "Booking Confirmed" },
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

  const sport = facility?.sports.find((s) => s.facilitySportId === sportId) ?? null;
  const sportName = sport?.name ?? "";

  // Courts carry no photograph of their own, so the card thumbnails reuse
  // the venue's hero — the same image the landing page resolved.
  const heroImage = useMemo(
    () =>
      facility
        ? resolveFacilityHeroImage(facility, sport)
        : ({ src: null, alt: "", source: "none" } as HeroImage),
    [facility, sport],
  );

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

  const showSummaryPanel = Boolean(selection) && step !== "select" && step !== "done";

  if (step === "done" && confirmation) {
    return <Confirmed confirmation={confirmation} />;
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
          <StepBar current={step} />

          <div className="mt-6">
            <h1 className="text-lg font-semibold tracking-tight sm:text-2xl">Book Your Court</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {step === "select"
                ? "Quick and easy court booking for everyone."
                : step === "details"
                  ? "Tell us who's playing."
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
                  heroImage={heroImage}
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

            {/* The desktop summary panel is for the later steps: on step 1
                the sticky bar below already shows the same figures, and two
                copies of them side by side reads as a mistake. */}
            {showSummaryPanel && selection && (
              <SummaryPanel
                open={summaryOpen}
                onToggle={() => setSummaryOpen((v) => !v)}
                facility={facility}
                sportName={sportName}
                selection={selection}
              />
            )}
          </div>
        </div>

        <BookingActionBar
          step={step}
          facility={facility}
          sportName={sportName}
          selection={selection}
          submitting={submitting}
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

function StepBar({ current }: { current: Step }) {
  const index = STEPS.findIndex((s) => s.id === current);
  return (
    <ol className="flex items-center" aria-label="Booking steps">
      {STEPS.map((s, i) => {
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
            {i < STEPS.length - 1 && (
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
  selection,
  onSelect,
  currency,
  heroImage,
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
  heroImage: HeroImage;
}) {
  const [showAllCourts, setShowAllCourts] = useState(false);

  // The court cards act as a filter for the slot rail below: pick a court,
  // then a time on it. Defaults to the first court that has anything free.
  const [courtId, setCourtId] = useState<string | null>(null);
  const activeCourtId =
    courtId ?? selection?.courtId ?? courts.find((c) => c.slots.some((s) => s.available))?.courtId ?? courts[0]?.courtId ?? null;
  const activeCourt = courts.find((c) => c.courtId === activeCourtId) ?? null;

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
            <h2 className="text-sm font-semibold">Select a Court</h2>
            <p className="text-xs text-muted-foreground">Available courts for the selected date</p>
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
                image={heroImage}
                currency={currency}
                selected={court.courtId === activeCourtId}
                onSelect={() => setCourtId(court.courtId)}
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
        <h2 className="text-sm font-semibold">Select Time Slot</h2>
        <p className="text-xs text-muted-foreground">All times shown in IST</p>

        {loading ? (
          <div className="mt-3 flex gap-2">
            {[0, 1, 2, 3, 4].map((i) => (
              <Skeleton key={i} className="h-14 w-32 shrink-0 rounded-xl" />
            ))}
          </div>
        ) : !activeCourt ? null : activeCourt.slots.length === 0 ? (
          <p className="mt-3 rounded-lg border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
            No times are open on this court. Try another court or date.
          </p>
        ) : (
          <SlotRail
            court={activeCourt}
            currency={currency}
            selection={selection}
            onSelect={onSelect}
          />
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
  image,
  currency,
  selected,
  onSelect,
}: {
  court: PublicBookingCourt;
  image: HeroImage;
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
      <div className="relative aspect-[4/3] w-full bg-muted">
        {image.src ? (
          <Image src={image.src} alt="" fill sizes="240px" className="object-cover" />
        ) : (
          <div className="flex h-full items-center justify-center bg-gradient-to-br from-primary/15 to-muted">
            <LayoutGrid className="h-6 w-6 text-muted-foreground" aria-hidden />
          </div>
        )}
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

/** Horizontally scrolling time slots, with arrows on pointer devices. */
function SlotRail({
  court,
  currency,
  selection,
  onSelect,
}: {
  court: PublicBookingCourt;
  currency: string;
  selection: Selection | null;
  onSelect: (s: Selection) => void;
}) {
  const railRef = useRef<HTMLDivElement>(null);

  const scrollBy = (direction: 1 | -1) => {
    railRef.current?.scrollBy({ left: direction * 240, behavior: "smooth" });
  };

  return (
    <div className="mt-3 flex items-center gap-2">
      <RailButton direction="left" onClick={() => scrollBy(-1)} />
      <div
        ref={railRef}
        className="flex flex-1 snap-x gap-2 overflow-x-auto scroll-smooth pb-1"
      >
        {court.slots.map((slot) => {
          const active = selection?.courtId === court.courtId && selection.startTime === slot.startTime;
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
  selection,
  submitting,
  onBack,
  onNext,
}: {
  step: Step;
  facility: PublicBookingFacility;
  sportName: string;
  selection: Selection | null;
  submitting: boolean;
  onBack: () => void;
  onNext: () => void;
}) {
  if (step === "done") return null;

  const canContinue = step === "select" ? Boolean(selection) : true;
  const label = step === "review" ? (submitting ? "Confirming booking…" : "Confirm Booking") : "Continue";

  return (
    <div className="sticky bottom-0 z-10 border-t border-border bg-card/95 px-4 py-3 backdrop-blur sm:px-8">
      <div className="flex items-center gap-3">
        <div className="min-w-0 flex-1">
          {selection ? (
            <>
              {/* The full context line has room only on larger screens; the
                  phone keeps the total, which is what a player checks. */}
              <p className="hidden truncate text-xs text-muted-foreground sm:block">
                {[sportName, facility.facilityName, selection.courtName].filter(Boolean).join(" • ")}
              </p>
              <p className="hidden truncate text-xs text-muted-foreground sm:block">
                {formatBookingDate(selection.startTime)} • {formatSlotRange(selection.startTime, selection.endTime)} •{" "}
                {durationLabel(selection.startTime, selection.endTime)}
              </p>
              <p className="text-[11px] text-muted-foreground sm:hidden">Total</p>
              <p className="text-base font-semibold text-primary sm:hidden">
                {formatMoney(selection.priceMinor, facility.currency)}
              </p>
            </>
          ) : (
            <p className="text-xs text-muted-foreground">Pick a court and time to continue.</p>
          )}
        </div>

        {selection && (
          <div className="hidden text-right sm:block">
            <p className="text-[11px] text-muted-foreground">Total</p>
            <p className="text-lg font-semibold text-primary">
              {formatMoney(selection.priceMinor, facility.currency)}
            </p>
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
          {label}
          {!submitting && <ArrowRight className="h-4 w-4" aria-hidden />}
        </Button>
      </div>

      {step === "select" && selection && (
        <p className="mt-1 hidden text-right text-[11px] text-muted-foreground sm:block">
          You can review your booking next
        </p>
      )}
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
