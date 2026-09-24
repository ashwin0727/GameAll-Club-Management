"use client";

import { useEffect, useState } from "react";
import { Calendar, CalendarDays, Clock, Info, MapPin, Pencil, User } from "lucide-react";
import { Card } from "@/components/ui/card";
import { getPlayingAreasService } from "@/services/playing-areas";
import { monthlyEquivalentInr, planFeatures, splitPlanName } from "@/features/memberships/plan-insights";
import { PLAN_CARD_THEMES } from "@/features/memberships/components/plan-card";
import type { WizardDraft, WizardStep } from "@/features/memberships/add-member-wizard";
import type { ScheduleRange } from "@/features/memberships/playing-schedule";
import type { MembershipPlan } from "@/features/memberships/types";
import { cn } from "@/lib/utils";

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}
function initials(name: string): string {
  return name.split(" ").filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join("");
}
function fmtDate(iso: string): string {
  return new Date(`${iso}T00:00:00`).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function PanelHeader({
  icon: Icon,
  tone,
  title,
  onEdit,
  locked,
}: {
  icon: React.ComponentType<{ className?: string }>;
  tone: string;
  title: string;
  onEdit?: () => void;
  /** Once a payment link has been generated, nothing here can change until payment completes —
   *  further edits happen on the Edit Membership page after that. */
  locked?: boolean;
}) {
  return (
    <div className="flex items-center justify-between gap-2">
      <div className="flex items-center gap-2">
        <span className={cn("flex h-7 w-7 shrink-0 items-center justify-center rounded-lg", tone)}>
          <Icon className="h-3.5 w-3.5" aria-hidden />
        </span>
        <p className="text-sm font-bold text-black dark:text-foreground">{title}</p>
      </div>
      {onEdit && !locked && (
        <button
          type="button"
          onClick={onEdit}
          className="flex items-center gap-1 text-xs font-medium text-muted-foreground transition-colors hover:text-foreground"
        >
          <Pencil className="h-3 w-3" aria-hidden />
          Edit
        </button>
      )}
    </div>
  );
}

/**
 * The condensed "who/what/when" recap shown beside Review & Confirm and Payment — everything
 * gathered in Steps 1-3, so the member doesn't have to leave the payment screen to check a
 * detail. "Edit" jumps straight back to the step that field came from.
 */
export function MemberContextPanel({
  facilityId,
  draft,
  photoPreview,
  plans,
  selectedPlan,
  scheduleRanges,
  onEditStep,
  locked = false,
}: {
  facilityId: string;
  draft: WizardDraft;
  photoPreview: string | null;
  plans: MembershipPlan[];
  selectedPlan: MembershipPlan | undefined;
  scheduleRanges: ScheduleRange[];
  onEditStep: (step: WizardStep) => void;
  /** Once a payment link has been generated, every "Edit" here is disabled — see PanelHeader. */
  locked?: boolean;
}) {
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
  const scheduleLine = scheduleRanges
    .map((r) => `${formatClock12(r.startTime)} - ${formatClock12(r.endTime)}`)
    .join(", ");

  return (
    <div className="space-y-4">
      <Card className="space-y-3 rounded-xl p-4">
        <PanelHeader icon={User} tone="bg-blue-500/15 text-blue-600 dark:text-blue-400" title="Member Summary" onEdit={() => onEditStep(1)} locked={locked} />
        <div className="flex items-center gap-3">
          <span className="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-full bg-muted text-xs font-semibold text-muted-foreground">
            {photoPreview ? (
              // eslint-disable-next-line @next/next/no-img-element -- a local object URL, not a remote/optimizable image
              <img src={photoPreview} alt="" className="h-full w-full object-cover" />
            ) : (
              initials(draft.fullName || "?")
            )}
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-1.5">
              <p className="truncate text-sm font-bold text-black dark:text-foreground">{draft.fullName}</p>
              <span className="whitespace-nowrap rounded-full bg-success/15 px-1.5 py-0.5 text-[10px] font-semibold text-success">
                New Member
              </span>
            </div>
            <p className="truncate text-xs text-muted-foreground">
              {draft.countryCode} {draft.phone}
              {draft.email ? ` | ${draft.email}` : ""}
            </p>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-x-3 gap-y-2.5 border-t border-border pt-3 text-xs">
          {draft.dateOfBirth && (
            <div className="flex items-start gap-1.5">
              <Calendar className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
              <div>
                <p className="text-muted-foreground">Date of Birth</p>
                <p className="font-medium text-foreground">{fmtDate(draft.dateOfBirth)}</p>
              </div>
            </div>
          )}
          {draft.gender && (
            <div className="flex items-start gap-1.5">
              <User className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
              <div>
                <p className="text-muted-foreground">Gender</p>
                <p className="font-medium text-foreground">{capitalize(draft.gender)}</p>
              </div>
            </div>
          )}
          {(draft.address || draft.city || draft.pincode) && (
            <div className="col-span-2 flex items-start gap-1.5">
              <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
              <div className="min-w-0">
                <p className="text-muted-foreground">Address</p>
                <p className="truncate font-medium text-foreground">
                  {[draft.address, draft.city, draft.pincode].filter(Boolean).join(", ")}
                </p>
              </div>
            </div>
          )}
        </div>
      </Card>

      <Card className="space-y-3 rounded-xl p-4">
        <PanelHeader icon={CalendarDays} tone="bg-success/15 text-success" title="Membership Plan" onEdit={() => onEditStep(2)} locked={locked} />
        <div className={cn("space-y-2 rounded-xl p-3", theme.surface)}>
          <div className="flex items-start gap-2.5">
            <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-lg", theme.chip)}>
              <CalendarDays className="h-4 w-4" aria-hidden />
            </span>
            <div>
              <p className="text-sm font-bold text-black dark:text-foreground">{name.main}</p>
              <p className="text-xs tabular-nums text-muted-foreground">
                {inr(selectedPlan?.priceInr ?? draft.membershipFeeInr)}
                {months === 1 ? " / month" : ` (${inr(perMonth)} / month)`}
              </p>
            </div>
          </div>
          {selectedPlan && (
            <ul className="space-y-1">
              {planFeatures(selectedPlan).map((f) => (
                <li key={f} className="flex items-center gap-1.5 text-xs text-foreground/80">
                  <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", theme.tick)} aria-hidden />
                  {f}
                </li>
              ))}
            </ul>
          )}
        </div>
      </Card>

      <Card className="space-y-3 rounded-xl p-4">
        <PanelHeader icon={Clock} tone="bg-blue-500/15 text-blue-600 dark:text-blue-400" title="Playing Schedule" onEdit={() => onEditStep(3)} locked={locked} />
        {draft.schedule.times.length === 0 ? (
          <p className="text-xs text-muted-foreground">No dedicated court time selected.</p>
        ) : (
          <div className="space-y-2 text-xs">
            <div className="flex items-start gap-1.5">
              <CalendarDays className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
              <p className="font-medium text-foreground">{dayList(draft.schedule.daysOfWeek)}</p>
            </div>
            <div className="flex items-start gap-1.5">
              <Clock className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
              <p className="font-medium text-foreground">{scheduleLine}</p>
            </div>
            <div className="flex items-start gap-1.5">
              <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
              <p className="font-medium text-foreground">{courtName ?? "—"}</p>
            </div>
          </div>
        )}
        {draft.paymentTab !== "link" && (
          <div className="flex items-start gap-2 rounded-lg bg-blue-500/10 p-3">
            <Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-blue-600 dark:text-blue-400" aria-hidden />
            <div className="text-xs text-foreground/80">
              <p className="font-semibold text-blue-700 dark:text-blue-400">After saving the payment</p>
              <p>You will be redirected to create the member. The membership will be activated immediately after.</p>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}

const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
function dayList(days: number[]): string {
  return [...new Set(days)].sort().map((d) => DAY_ABBR[d]).join(", ");
}
function formatClock12(time: string): string {
  const [hStr, mStr] = time.split(":");
  const h = Number(hStr ?? 0);
  const m = Number(mStr ?? 0);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}
