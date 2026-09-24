"use client";

import { useEffect, useState } from "react";
import { getPlayingAreasService } from "@/services/playing-areas";
import {
  BadgeCheck,
  Calendar,
  CalendarDays,
  Check,
  Clock,
  Mail,
  MapPin,
  Pencil,
  Phone,
  ShieldCheck,
  User,
  Wallet,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { DAY_OPTIONS } from "@/features/memberships/slot-form";
import { formatClock } from "@/features/memberships/slot-format";
import {
  billingIntervalLabel,
  currentBillingPeriod,
  durationLabel,
  monthlyEquivalentInr,
  nextBillingDate,
  planFeatures,
  splitPlanName,
} from "@/features/memberships/plan-insights";
import { PLAN_CARD_THEMES } from "@/features/memberships/components/plan-card";
import type { Charges, WizardDraft, WizardStep } from "@/features/memberships/add-member-wizard";
import type { ScheduleRange } from "@/features/memberships/playing-schedule";
import type { MembershipPlan } from "@/features/memberships/types";
import { cn } from "@/lib/utils";

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}
/** "male" -> "Male" — the stored value stays lowercase; only the display is capitalized. */
function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function initials(name: string): string {
  return name.split(" ").filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join("");
}
function fmtDate(iso: string | Date): string {
  const d = typeof iso === "string" ? new Date(`${iso}T00:00:00`) : iso;
  return d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

function SectionHeader({
  icon: Icon,
  tone,
  title,
  subtitle,
  onEdit,
}: {
  icon: React.ComponentType<{ className?: string }>;
  tone: string;
  title: string;
  subtitle?: string;
  onEdit?: () => void;
}) {
  return (
    <div className="flex items-start justify-between gap-3">
      <div className="flex items-center gap-2.5">
        <span className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-lg", tone)}>
          <Icon className="h-4 w-4" aria-hidden />
        </span>
        <div>
          <p className="text-sm font-bold text-black dark:text-foreground">{title}</p>
          {subtitle && <p className="text-xs text-muted-foreground">{subtitle}</p>}
        </div>
      </div>
      {onEdit && (
        <button
          type="button"
          onClick={onEdit}
          className="flex h-8 items-center gap-1.5 rounded-lg border border-input bg-card px-2.5 text-xs font-medium text-foreground transition-colors hover:bg-accent"
        >
          <Pencil className="h-3 w-3" aria-hidden />
          Edit
        </button>
      )}
    </div>
  );
}

function Detail({ icon: Icon, label, value }: { icon: React.ComponentType<{ className?: string }>; label: string; value: string }) {
  return (
    <div className="flex items-start gap-2">
      <Icon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
      <div className="min-w-0">
        <p className="text-[11px] text-muted-foreground">{label}</p>
        <p className="truncate text-sm font-medium text-foreground">{value}</p>
      </div>
    </div>
  );
}

function SummaryRow({
  icon: Icon,
  label,
  value,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: string;
}) {
  return (
    <div className="flex items-center gap-3 py-2.5 text-sm">
      <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-blue-500/15 text-blue-600 dark:text-blue-400">
        <Icon className="h-3.5 w-3.5" aria-hidden />
      </span>
      {/* A fixed-width label column, not justify-between — the value starts at a consistent
          left position down the list instead of being pushed flush against the right edge. */}
      <span className="w-[104px] shrink-0 text-muted-foreground">{label}</span>
      <span className="min-w-0 flex-1 text-left font-medium text-foreground">{value}</span>
    </div>
  );
}

const NEXT_STEPS = [
  { title: "Confirm and create member", sub: 'Click on "Create Member" to register the member.' },
  { title: "Complete payment (if required)", sub: "Collect the membership fee and mark payment status." },
  { title: "Member will be notified", sub: "A welcome message will be sent with all the details." },
];

/**
 * Step 4, "Review & Confirm" — everything gathered from the first three steps, laid out as the
 * design's two columns: Member / Plan / Schedule / Communication on the left, a flattened
 * Summary and the Next Steps guide on the right. Every "Edit" jumps straight to the step that
 * field came from, rather than stepping through the wizard again.
 */
export function MembershipReviewStep({
  facilityId,
  draft,
  photoPreview,
  plans,
  selectedPlan,
  planEndDate,
  scheduleRanges,
  charges,
  onEditStep,
}: {
  facilityId: string;
  draft: WizardDraft;
  photoPreview: string | null;
  plans: MembershipPlan[];
  selectedPlan: MembershipPlan | undefined;
  planEndDate: Date | null;
  scheduleRanges: ScheduleRange[];
  charges: Charges;
  onEditStep: (step: WizardStep) => void;
}) {
  // The schedule draft only carries the court's id; its name lives in the same list the
  // picker itself loads, so it's fetched again here for display purposes only.
  const [courtName, setCourtName] = useState<string | null>(null);
  useEffect(() => {
    if (!draft.schedule.courtId) {
      setCourtName(null);
      return;
    }
    let cancelled = false;
    getPlayingAreasService()
      .getPlayingAreas(facilityId)
      .then((areas) => {
        if (!cancelled) setCourtName(areas.find((a) => a.id === draft.schedule.courtId)?.name ?? null);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [facilityId, draft.schedule.courtId]);

  const planIndex = Math.max(0, plans.findIndex((p) => p.id === draft.planId));
  const theme = PLAN_CARD_THEMES[planIndex % PLAN_CARD_THEMES.length]!;
  const name = selectedPlan ? splitPlanName(selectedPlan.name) : { main: draft.planName, detail: null };
  const months = selectedPlan ? Math.max(1, Math.round(selectedPlan.durationDays / 30)) : 1;
  const perMonth = selectedPlan ? monthlyEquivalentInr(selectedPlan.priceInr, selectedPlan.durationDays) : 0;
  const isRecurring = selectedPlan?.planType === "RECURRING";
  const billingPeriod = isRecurring ? currentBillingPeriod(draft.startDate, draft.durationDays) : null;

  const emergency = [draft.emergencyName, draft.emergencyPhone && `${draft.emergencyCountryCode} ${draft.emergencyPhone}`]
    .filter(Boolean)
    .join(" — ");

  const scheduleLine =
    scheduleRanges.length === 0
      ? "No dedicated slot"
      : scheduleRanges.map((r) => `${formatClock(r.startTime)} - ${formatClock(r.endTime)}`).join(", ");
  const dayLabels = DAY_OPTIONS.filter((d) => draft.schedule.daysOfWeek.includes(d.value)).map((d) => d.label);

  return (
    <div className="grid grid-cols-1 gap-5 xl:grid-cols-[1fr_320px]">
      <div className="space-y-4">
        <Card className="space-y-4 rounded-xl p-4">
          <SectionHeader icon={User} tone="bg-blue-500/15 text-blue-600 dark:text-blue-400" title="Member Details" onEdit={() => onEditStep(1)} />

          <div className="flex items-center gap-3 border-b border-border pb-4">
            <span className="flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-full bg-muted text-sm font-semibold text-muted-foreground">
              {photoPreview ? (
                // eslint-disable-next-line @next/next/no-img-element -- a local object URL, not a remote/optimizable image
                <img src={photoPreview} alt="" className="h-full w-full object-cover" />
              ) : (
                initials(draft.fullName || "?")
              )}
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <p className="truncate text-sm font-bold text-black dark:text-foreground">{draft.fullName}</p>
                <span className="whitespace-nowrap rounded-full bg-success/15 px-2 py-0.5 text-[11px] font-semibold text-success">
                  New Member
                </span>
              </div>
              <p className="mt-0.5 truncate text-xs text-muted-foreground">
                {draft.countryCode} {draft.phone}
                {draft.email ? ` | ${draft.email}` : ""}
              </p>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-x-4 gap-y-3">
            {draft.dateOfBirth && <Detail icon={Calendar} label="Date of Birth" value={fmtDate(draft.dateOfBirth)} />}
            {draft.gender && <Detail icon={User} label="Gender" value={capitalize(draft.gender)} />}
            {(draft.address || draft.city || draft.pincode) && (
              <Detail
                icon={MapPin}
                label="Address"
                value={[draft.address, draft.city, draft.pincode].filter(Boolean).join(", ")}
              />
            )}
            {emergency && <Detail icon={Phone} label="Emergency Contact" value={emergency} />}
          </div>
        </Card>

        <Card className="space-y-4 rounded-xl p-4">
          <SectionHeader
            icon={BadgeCheck}
            tone="bg-success/15 text-success"
            title="Membership Plan"
            onEdit={() => onEditStep(2)}
          />

          <div className={cn("flex flex-col gap-4 rounded-xl p-4 sm:flex-row sm:items-center sm:justify-between", theme.surface)}>
            <div className="flex items-start gap-3">
              <span className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-xl", theme.chip)}>
                <CalendarDays className="h-5 w-5" aria-hidden />
              </span>
              <div>
                <p className="text-sm font-bold text-black dark:text-foreground">{name.main}</p>
                <p className="text-xs text-muted-foreground">Valid for {durationLabel(draft.durationDays)}</p>
                <ul className="mt-2 space-y-1">
                  {selectedPlan &&
                    planFeatures(selectedPlan).map((f) => (
                      <li key={f} className="flex items-center gap-1.5 text-xs text-foreground/80">
                        <span className={cn("flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full", theme.tick)}>
                          <Check className="h-2 w-2 text-white" strokeWidth={4} aria-hidden />
                        </span>
                        {f}
                      </li>
                    ))}
                </ul>
              </div>
            </div>

            <div className="flex shrink-0 items-start justify-between gap-4 sm:flex-col sm:items-end">
              <p className="whitespace-nowrap text-right">
                <span className="text-lg font-bold tabular-nums text-black dark:text-foreground">{inr(draft.membershipFeeInr)}</span>
                <span className="text-xs text-muted-foreground"> {months === 1 ? "/ month" : `(${inr(perMonth)} / month)`}</span>
              </p>
              <div className="rounded-lg bg-card/70 p-2 text-xs">
                <p className="flex items-center gap-1.5 text-muted-foreground">
                  <Calendar className="h-3 w-3" aria-hidden />
                  {isRecurring ? "Membership Start" : "Plan Start Date"}
                </p>
                <p className="font-medium text-foreground">{fmtDate(draft.startDate)}</p>
                {isRecurring ? (
                  <>
                    <p className="mt-1.5 flex items-center gap-1.5 text-muted-foreground">
                      <Calendar className="h-3 w-3" aria-hidden />
                      Billing Cycle
                    </p>
                    <p className="font-medium text-foreground capitalize">{billingIntervalLabel(draft.durationDays)}</p>
                    <p className="mt-1.5 flex items-center gap-1.5 text-muted-foreground">
                      <Calendar className="h-3 w-3" aria-hidden />
                      Next Billing Date
                    </p>
                    <p className="font-medium text-foreground">{fmtDate(nextBillingDate(draft.startDate, draft.durationDays))}</p>
                    <p className="mt-1.5 flex items-center gap-1.5 text-muted-foreground">
                      <Calendar className="h-3 w-3" aria-hidden />
                      Current Billing Period
                    </p>
                    <p className="font-medium text-foreground">
                      {fmtDate(billingPeriod!.start)} → {fmtDate(billingPeriod!.end)}
                    </p>
                  </>
                ) : (
                  planEndDate && (
                    <>
                      <p className="mt-1.5 flex items-center gap-1.5 text-muted-foreground">
                        <Calendar className="h-3 w-3" aria-hidden />
                        Plan End Date
                      </p>
                      <p className="font-medium text-foreground">{fmtDate(planEndDate)}</p>
                    </>
                  )
                )}
              </div>
            </div>
          </div>
        </Card>

        <Card className="space-y-4 rounded-xl p-4">
          <SectionHeader icon={Clock} tone="bg-blue-500/15 text-blue-600 dark:text-blue-400" title="Playing Schedule" onEdit={() => onEditStep(3)} />

          {draft.schedule.times.length === 0 ? (
            <p className="text-sm text-muted-foreground">No dedicated court time selected.</p>
          ) : (
            <>
              <div className="flex flex-wrap gap-2">
                {DAY_OPTIONS.map((d) => {
                  const on = draft.schedule.daysOfWeek.includes(d.value);
                  return (
                    <span
                      key={d.value}
                      className={cn(
                        "rounded-lg px-3 py-1.5 text-xs font-medium",
                        on ? "bg-[#0B9B63] text-white" : "bg-muted text-muted-foreground",
                      )}
                    >
                      {d.label}
                    </span>
                  );
                })}
              </div>

              <div className="grid grid-cols-2 gap-4">
                <Detail icon={Clock} label="Playing Time" value={scheduleLine} />
                <Detail icon={MapPin} label="Court" value={courtName ?? "—"} />
              </div>

              <div className="flex items-start gap-2 rounded-lg bg-blue-500/10 p-3 text-xs text-foreground/80">
                <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-blue-600 dark:text-blue-400" aria-hidden />
                These time slots will be reserved for this member throughout the membership period. Guest bookings will not
                be allowed during these times.
              </div>
            </>
          )}
        </Card>

        <Card className="space-y-3 rounded-xl p-4">
          <SectionHeader icon={Mail} tone="bg-purple-500/15 text-purple-600 dark:text-purple-400" title="Communication Preferences" />
          <div className={cn("flex items-start gap-2 rounded-lg p-2.5", draft.sendWelcome ? "bg-success/10" : "bg-muted/40")}>
            <span
              className={cn(
                "mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full",
                draft.sendWelcome ? "bg-[#0B9B63]" : "border-2 border-input",
              )}
            >
              {draft.sendWelcome && <Check className="h-2.5 w-2.5 text-white" strokeWidth={4} aria-hidden />}
            </span>
            <div>
              <p className="text-sm font-medium text-foreground">
                {draft.sendWelcome ? "Send welcome message to member" : "Welcome message won't be sent"}
              </p>
              <p className="text-xs text-muted-foreground">Member will receive an SMS/Email with membership details.</p>
            </div>
          </div>
        </Card>
      </div>

      <div className="space-y-4">
        <Card className="space-y-1 rounded-xl p-4">
          <div className="flex items-center gap-2.5 pb-1">
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-blue-500/15 text-blue-600 dark:text-blue-400">
              <ShieldCheck className="h-4 w-4" aria-hidden />
            </span>
            <div>
              <p className="text-sm font-bold text-black dark:text-foreground">Summary</p>
              <p className="text-xs text-muted-foreground">Please review all the details before creating the member.</p>
            </div>
          </div>
          <div className="divide-y divide-border">
            <SummaryRow icon={User} label="Name" value={draft.fullName} />
            <SummaryRow icon={Phone} label="Phone" value={`${draft.countryCode} ${draft.phone}`.trim()} />
            {draft.email && <SummaryRow icon={Mail} label="Email" value={draft.email} />}
            <SummaryRow icon={CalendarDays} label="Plan" value={name.main} />
            <SummaryRow icon={CalendarDays} label="Plan Duration" value={durationLabel(draft.durationDays)} />
            <SummaryRow icon={Calendar} label="Start Date" value={fmtDate(draft.startDate)} />
            {planEndDate && <SummaryRow icon={Calendar} label="End Date" value={fmtDate(planEndDate)} />}
            {dayLabels.length > 0 && <SummaryRow icon={CalendarDays} label="Playing Days" value={dayLabels.join(", ")} />}
            {scheduleRanges.length > 0 && <SummaryRow icon={Clock} label="Playing Time" value={scheduleLine} />}
            {draft.schedule.courtId && <SummaryRow icon={MapPin} label="Court" value={courtName ?? "—"} />}
            <SummaryRow icon={Wallet} label="Total Payable" value={inr(charges.total)} />
          </div>
        </Card>

        <Card className="space-y-4 rounded-xl p-4">
          <div className="flex items-center gap-2.5">
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-success/15 text-success">
              <BadgeCheck className="h-4 w-4" aria-hidden />
            </span>
            <p className="text-sm font-bold text-black dark:text-foreground">Next Steps</p>
          </div>
          <ol>
            {NEXT_STEPS.map((s, i) => (
              <li key={s.title} className="relative flex items-start gap-3 pb-5 last:pb-0">
                {/* The connecting line between numbers — one per step except the last, each
                    reaching down to the next circle rather than one continuous line drawn
                    separately (which would run behind the final circle with nothing below it). */}
                {i < NEXT_STEPS.length - 1 && (
                  <span className="absolute left-3 top-6 h-[calc(100%-1.25rem)] w-px bg-success/25" aria-hidden />
                )}
                <span className="relative z-10 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-success/15 text-xs font-semibold text-success">
                  {i + 1}
                </span>
                <div>
                  <p className="text-sm font-medium text-foreground">{s.title}</p>
                  <p className="text-xs text-muted-foreground">{s.sub}</p>
                </div>
              </li>
            ))}
          </ol>

          <div className="flex items-start gap-2.5 rounded-xl bg-success/10 p-4">
            <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-success" aria-hidden />
            <div>
              <p className="text-sm font-semibold text-success">You&apos;re almost done!</p>
              <p className="text-xs text-foreground/80">
                Once confirmed, the member&apos;s court slots will be blocked and guest bookings won&apos;t be allowed
                during these times.
              </p>
            </div>
          </div>
        </Card>
      </div>
    </div>
  );
}
