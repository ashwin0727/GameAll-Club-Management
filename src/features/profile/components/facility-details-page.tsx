"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Clock, Grid2x2, IndianRupee, LayoutGrid, Pencil, Trophy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { PageMessage, SectionCard, SubPageHeader } from "@/features/profile/components/profile-shared";
import { EditSetupDialog, sectionForHref, type SetupSection } from "@/features/profile/components/edit-setup-dialog";
import { getOnboardingService } from "@/services/onboarding";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getPricingService } from "@/services/pricing";
import { Card } from "@/components/ui/card";
import { groupCustomized, PeriodList } from "@/features/pricing/components/pricing-summary";
import { rulesToPeriods } from "@/features/pricing/components/types";
import type { PricingRule } from "@/features/pricing/types";
import type { PricingSummaryEntry, SportSummaryEntry } from "@/features/onboarding-summary/types";

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const TILE_TINTS = [
  "bg-emerald-50 text-emerald-900 dark:bg-emerald-500/10 dark:text-emerald-200",
  "bg-blue-50 text-blue-900 dark:bg-blue-500/10 dark:text-blue-200",
  "bg-orange-50 text-orange-900 dark:bg-orange-500/10 dark:text-orange-200",
  "bg-lime-50 text-lime-900 dark:bg-lime-500/10 dark:text-lime-200",
  "bg-violet-50 text-violet-900 dark:bg-violet-500/10 dark:text-violet-200",
];

function CountStat({ icon: Icon, tint, value, label }: { icon: React.ComponentType<{ className?: string }>; tint: string; value: number; label: string }) {
  return (
    <div className="flex min-w-0 items-center gap-3 px-3 py-3 sm:px-4">
      <span className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${tint}`}>
        <Icon className="h-5 w-5" />
      </span>
      <div className="min-w-0">
        <p className="text-xl font-semibold leading-tight">{value}</p>
        <p className="truncate text-xs text-muted-foreground">{label}</p>
      </div>
    </div>
  );
}

/** Courts & Sports at a glance: how many courts, how many are bookable, how many sports — and which sports. */
function CourtsAndSportsCard({
  sports,
  totalCourts,
  activeCourts,
  onManage,
}: {
  sports: SportSummaryEntry[];
  totalCourts: number;
  activeCourts: number;
  onManage?: () => void;
}) {
  return (
    <Card className="space-y-4 p-4 sm:p-5">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-base font-semibold">Courts</h2>
        {onManage && (
          <Button type="button" variant="outline" size="sm" onClick={onManage}>
            <Pencil className="mr-1.5 h-3.5 w-3.5" aria-hidden /> Manage
          </Button>
        )}
      </div>

      <div className="grid grid-cols-3 divide-x divide-border rounded-xl bg-muted/40">
        <CountStat icon={LayoutGrid} tint="bg-emerald-100 text-emerald-600 dark:bg-emerald-500/15 dark:text-emerald-400" value={totalCourts} label="Total Courts" />
        <CountStat icon={Grid2x2} tint="bg-blue-100 text-blue-600 dark:bg-blue-500/15 dark:text-blue-400" value={activeCourts} label="Active Courts" />
        <CountStat icon={Trophy} tint="bg-violet-100 text-violet-600 dark:bg-violet-500/15 dark:text-violet-400" value={sports.length} label="Sports" />
      </div>

      <div>
        <h3 className="mb-3 text-sm font-semibold">Sports Available</h3>
        {sports.length === 0 ? (
          <p className="text-sm text-muted-foreground">No sports configured yet.</p>
        ) : (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {sports.map((sport, i) => (
              <div
                key={sport.facilitySportId}
                className={`flex flex-col items-center gap-2 rounded-xl px-3 py-4 text-center ${TILE_TINTS[i % TILE_TINTS.length]}`}
              >
                <span className="text-3xl" aria-hidden>
                  {sport.sportIcon}
                </span>
                <span className="text-sm font-medium">{sport.sportName}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </Card>
  );
}

/**
 * One sport's rates exactly as saved: its default rate (if it has one), then every court with a rate of its own. Courts
 * on the same rates are shown once ("All 3 Courts"), and a sport priced entirely per court shows no default line.
 */
function SportPricing({ entry, rules, areaCounts }: { entry: PricingSummaryEntry; rules: PricingRule[]; areaCounts: SportSummaryEntry[] }) {
  const sport = areaCounts.find((x) => x.facilitySportId === entry.facilitySportId);
  const areas = sport?.playingAreas ?? [];
  const currency = entry.currency;
  const defaultRules = rules.filter((r) => r.facilitySportId === entry.facilitySportId && !r.playingAreaId);
  const customized = areas
    .map((a) => ({ areaName: a.name, periods: rulesToPeriods(rules.filter((r) => r.playingAreaId === a.id), currency) }))
    .filter((c) => c.periods.length > 0);
  const allCustomized = areas.length > 0 && customized.length === areas.length;

  return (
    <li className="space-y-1.5 py-3 text-sm first:pt-0 last:pb-0">
      <div className="flex items-center justify-between gap-3">
        <span className="flex items-center gap-2 font-medium">
          <IndianRupee className="h-4 w-4 text-muted-foreground" aria-hidden /> {entry.sportName}
        </span>
        <span className="text-xs text-muted-foreground">{allCustomized ? "Rate per court" : defaultRules.length > 0 ? "Default rate" : "No default rate"}</span>
      </div>
      {defaultRules.length > 0 && (
        <div className="pl-6 text-xs">
          <PeriodList periods={rulesToPeriods(defaultRules, currency)} currency={currency} />
        </div>
      )}
      {defaultRules.length === 0 && !allCustomized && customized.length === 0 && <p className="pl-6 text-xs text-muted-foreground">Not set</p>}
      {groupCustomized(customized).map((g) => {
        const coversAll = allCustomized && g.areaNames.length === areas.length && areas.length > 1;
        return (
          <div key={g.areaNames.join("|")} className="space-y-0.5 pl-6 text-xs">
            <p className="font-medium text-foreground">{coversAll ? `All ${areas.length} ${sport?.areaLabel.toLowerCase()}s` : g.areaNames.join(", ")}</p>
            <PeriodList periods={g.periods} currency={currency} />
          </div>
        );
      })}
    </li>
  );
}

/**
 * Manage Facility Details: everything entered while setting the facility up — sports, courts, timings, pricing — in
 * one place. The owner can jump straight to the setup step that changes any of it.
 */
export function FacilityDetailsPage() {
  const { data: user } = useCurrentUser();
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const summary = useQuery({
    queryKey: ["profile", "facility-summary", facility?.id],
    queryFn: () => getOnboardingService().getSetupSummary(facility!.id),
    enabled: !!facility,
    staleTime: 60_000,
  });

  const plan = useQuery({
    queryKey: ["profile", "pricing-plan", facility?.id],
    queryFn: () => getPricingService().getPricingPlan(facility!.id),
    enabled: !!facility,
    staleTime: 60_000,
  });
  const areas = useQuery({
    queryKey: ["profile", "playing-areas", facility?.id],
    queryFn: () => getPlayingAreasService().getPlayingAreas(facility!.id),
    enabled: !!facility,
    staleTime: 60_000,
  });
  const pricingRules = plan.data?.rules ?? [];
  const isOwner = !!facility && facility.ownerId === user?.id;
  const router = useRouter();
  const [editing, setEditing] = useState<SetupSection | null>(null);
  const edit = (section: SetupSection, label: string) =>
    isOwner ? (
      <Button type="button" variant="ghost" size="sm" className="h-8 text-xs" onClick={() => setEditing(section)}>
        {label}
      </Button>
    ) : undefined;

  const header = (
    <SubPageHeader
      title="Manage Facility Details"
      description="Your courts, sports, timings and pricing — everything you set up for your facility."
    />
  );

  if (facilityLoading || summary.isLoading) {
    return (
      <div className="space-y-4">
        {header}
        <Skeleton className="h-24 w-full rounded-xl" />
        <Skeleton className="h-48 w-full rounded-xl" />
        <Skeleton className="h-32 w-full rounded-xl" />
      </div>
    );
  }
  if (!facility) {
    return (
      <div className="space-y-4">
        {header}
        <PageMessage>No facility is set up for this account yet.</PageMessage>
      </div>
    );
  }
  if (summary.isError || !summary.data) {
    return (
      <div className="space-y-4">
        {header}
        <PageMessage tone="error">Unable to load your facility details. Please try again.</PageMessage>
      </div>
    );
  }

  const s = summary.data;
  // Courts that are switched on; an inactive court still exists but can't be booked.
  const activeCourts = (areas.data ?? []).filter((a) => a.status === "ACTIVE").length;
  const ready = s.setupStatus === "READY";
  const days = facility.membershipAccessDays;

  return (
    <div className="space-y-4">
      {header}

      {!ready && (
        <SectionCard title="Finish your setup">
          <ul className="space-y-2">
            {s.missingRequirements.map((req, i) => (
              <li key={`${req.code}-${i}`} className="flex items-center justify-between gap-3 text-sm">
                <span className="text-muted-foreground">{req.message}</span>
                {isOwner && (
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="shrink-0"
                    onClick={() => {
                      const section = sectionForHref(req.actionHref);
                      if (section) setEditing(section);
                      else if (req.code === "PAYOUT") router.push("/profile/payments");
                    }}
                  >
                    {req.actionLabel}
                  </Button>
                )}
              </li>
            ))}
          </ul>
        </SectionCard>
      )}

      <SectionCard title="Court Timings" description="When your facility is open." action={edit("hours", "Edit timings")}>
        {!s.operatingHoursGroups || s.operatingHoursGroups.length === 0 ? (
          <p className="text-sm text-muted-foreground">Operating hours aren&apos;t configured yet.</p>
        ) : (
          <ul className="divide-y divide-border">
            {s.operatingHoursGroups.map((g) => (
              <li key={g.label} className="flex flex-col gap-0.5 py-2 text-sm first:pt-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between">
                <span className="flex items-center gap-2 font-medium">
                  <Clock className="h-4 w-4 text-muted-foreground" aria-hidden /> {g.label}
                </span>
                <span className="text-muted-foreground">{g.description}</span>
              </li>
            ))}
          </ul>
        )}
      </SectionCard>

      <SectionCard title="Sports" description="Every sport you offer, and the courts or turfs under it." action={edit("sports", "Edit sports")}>
        {s.sports.length === 0 ? (
          <p className="text-sm text-muted-foreground">No sports configured yet.</p>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {s.sports.map((sport) => (
              <div key={sport.facilitySportId} className="rounded-lg border border-border p-3">
                <p className="flex items-center gap-2 text-sm font-semibold">
                  <span aria-hidden>{sport.sportIcon}</span>
                  {sport.sportName}
                  <span className="ml-auto text-xs font-normal text-muted-foreground">
                    {sport.playingAreas.length} {sport.areaLabel.toLowerCase()}
                    {sport.playingAreas.length === 1 ? "" : "s"}
                  </span>
                </p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {sport.playingAreas.length === 0 ? (
                    <span className="text-xs text-muted-foreground">None added</span>
                  ) : (
                    sport.playingAreas.map((a) => (
                      <span key={a.id} className="rounded-full bg-muted px-2.5 py-0.5 text-xs">
                        {a.name}
                      </span>
                    ))
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
        {isOwner && s.sports.length > 0 && (
          <Button type="button" variant="ghost" size="sm" className="h-8 text-xs" onClick={() => setEditing("courts")}>
            Edit courts
          </Button>
        )}
      </SectionCard>

      <CourtsAndSportsCard
        sports={s.sports}
        totalCourts={s.totalPlayingAreas}
        activeCourts={activeCourts}
        onManage={isOwner ? () => setEditing("courts") : undefined}
      />

      <SectionCard title="Membership Access Days" description="The days a member may use a court by default.">
        <div className="flex flex-wrap gap-1.5">
          {WEEKDAYS.map((d, i) => (
            <span
              key={d}
              className={
                days.includes(i)
                  ? "rounded-full bg-primary/15 px-3 py-1 text-xs font-medium text-primary"
                  : "rounded-full bg-muted px-3 py-1 text-xs text-muted-foreground line-through"
              }
            >
              {d}
            </span>
          ))}
        </div>
      </SectionCard>

      <SectionCard title="Pricing" description="What a booking costs, by sport and court." action={edit("pricing", "Edit pricing")}>
        {s.pricing.length === 0 ? (
          <p className="text-sm text-muted-foreground">Pricing isn&apos;t configured yet.</p>
        ) : (
          <ul className="divide-y divide-border">
            {s.pricing.map((p) => (
              <SportPricing key={p.facilitySportId} entry={p} rules={pricingRules} areaCounts={s.sports} />
            ))}
          </ul>
        )}
      </SectionCard>

      {editing && <EditSetupDialog section={editing} onClose={() => setEditing(null)} />}
    </div>
  );
}
