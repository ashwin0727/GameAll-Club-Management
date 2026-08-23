"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { CheckCircle2, AlertTriangle } from "lucide-react";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { FormMessage } from "@/features/auth/components/form-message";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { getOnboardingService } from "@/services/onboarding";
import { formatCurrency, PRICING_UNIT_LABEL } from "@/features/pricing/money";
import type { SetupSummary } from "@/features/onboarding-summary/types";

const ErrorState = dynamic(() =>
  import("@/components/shared/error-state").then((mod) => mod.ErrorState),
);

type LoadState = "loading" | "ready" | "forbidden" | "error";

export function SetupSummaryPage() {
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();

  const [summary, setSummary] = useState<SetupSummary | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("loading");
  const [completeError, setCompleteError] = useState<string | null>(null);
  const [isCompleting, setIsCompleting] = useState(false);

  async function load() {
    setLoadState("loading");
    try {
      const facility = await getFacilityService().getFacility();
      if (!facility) {
        router.replace("/onboarding/facility");
        return;
      }
      if (!user || facility.ownerId !== user.id) {
        setLoadState("forbidden");
        return;
      }

      const result = await getOnboardingService().getSetupSummary(facility.id);
      setSummary(result);
      setLoadState("ready");
    } catch {
      setLoadState("error");
    }
  }

  useEffect(() => {
    if (userLoading) return;
    if (!user) {
      router.replace("/login");
      return;
    }
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, userLoading, router]);

  async function handleComplete() {
    if (!summary) return;
    setIsCompleting(true);
    setCompleteError(null);
    try {
      await getOnboardingService().completeSetup(summary.facility.id);
      router.push("/dashboard");
    } catch {
      setCompleteError("Your setup could not be completed. Please try again.");
      setIsCompleting(false);
    }
  }

  if (userLoading || loadState === "loading") {
    return (
      <div className="space-y-6">
        <Skeleton className="h-20 w-full rounded-xl" />
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-32 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  if (loadState === "forbidden") {
    return <ErrorState title="Access denied" message="You don't have access to this facility." />;
  }

  if (loadState === "error" || !summary) {
    return (
      <div className="space-y-4 text-center">
        <p className="text-sm text-muted-foreground">Unable to load your facility setup.</p>
        <Button type="button" variant="outline" onClick={load}>
          Try Again
        </Button>
      </div>
    );
  }

  const { facility } = summary;

  if (facility.onboardingStep === "COMPLETED") {
    return (
      <div className="space-y-6 text-center">
        <CheckCircle2 className="mx-auto h-12 w-12 text-primary" aria-hidden="true" />
        <div>
          <h2 className="text-lg font-semibold">Your facility setup is already complete.</h2>
          <p className="mt-1 text-sm text-muted-foreground">{facility.name}</p>
        </div>
        <Button type="button" onClick={() => router.push("/dashboard")} className="min-w-[10rem]">
          Go to Dashboard
        </Button>
      </div>
    );
  }

  const isReady = summary.setupStatus === "READY";

  return (
    <div className="space-y-8">
      <div className="flex flex-col items-center gap-2 text-center">
        <CheckCircle2
          className={isReady ? "h-10 w-10 text-primary" : "h-10 w-10 text-muted-foreground"}
          aria-hidden="true"
        />
        <p className="text-sm text-muted-foreground">
          Your facility information is ready. You can now manage bookings, members, payments,
          courts and more from one place.
        </p>
      </div>

      {completeError && <FormMessage>{completeError}</FormMessage>}

      {/* Facility */}
      <Card className="space-y-3 p-5">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-sm font-semibold">Facility</h2>
          <Button type="button" variant="ghost" size="sm" className="h-9 px-2 text-xs" onClick={() => router.push("/onboarding/facility")}>
            Edit
          </Button>
        </div>
        <div>
          <p className="text-base font-semibold text-foreground">{facility.name}</p>
          <p className="text-sm text-muted-foreground">{facility.address.city}</p>
        </div>
        <p className="text-xs text-muted-foreground">
          {summary.totalSports} Sports · {summary.totalPlayingAreas} Playing Areas
        </p>
      </Card>

      {/* Sports & Courts */}
      <Card className="space-y-4 p-5">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-sm font-semibold">Sports &amp; Courts</h2>
          <div className="flex gap-1">
            <Button type="button" variant="ghost" size="sm" className="h-9 px-2 text-xs" onClick={() => router.push("/onboarding/sports")}>
              Edit Sports
            </Button>
            <Button type="button" variant="ghost" size="sm" className="h-9 px-2 text-xs" onClick={() => router.push("/onboarding/courts")}>
              Edit Courts
            </Button>
          </div>
        </div>
        {summary.sports.length === 0 ? (
          <p className="text-sm text-muted-foreground">No sports configured yet.</p>
        ) : (
          <div className="space-y-3">
            {summary.sports.map((sport) => (
              <div key={sport.facilitySportId} className="space-y-1">
                <p className="text-sm font-medium">
                  <span aria-hidden="true">{sport.sportIcon} </span>
                  {sport.sportName}
                </p>
                <p className="text-xs text-muted-foreground">
                  {sport.playingAreas.length === 0
                    ? `No ${sport.areaLabel.toLowerCase()}s added`
                    : sport.playingAreas.map((a) => a.name).join(", ")}
                </p>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Operating Hours */}
      <Card className="space-y-3 p-5">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-sm font-semibold">Operating Hours</h2>
          <Button type="button" variant="ghost" size="sm" className="h-9 px-2 text-xs" onClick={() => router.push("/onboarding/operating-hours")}>
            Edit Operating Hours
          </Button>
        </div>
        {!summary.operatingHoursGroups || summary.operatingHoursGroups.length === 0 ? (
          <p className="text-sm text-muted-foreground">Operating hours not configured yet.</p>
        ) : (
          <div className="space-y-1.5">
            {summary.operatingHoursGroups.map((group) => (
              <div key={group.label} className="flex flex-col text-sm sm:flex-row sm:items-baseline sm:gap-2">
                <span className="font-medium text-foreground">{group.label}</span>
                <span className="text-muted-foreground">{group.description}</span>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Pricing */}
      <Card className="space-y-3 p-5">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-sm font-semibold">Pricing</h2>
          <Button type="button" variant="ghost" size="sm" className="h-9 px-2 text-xs" onClick={() => router.push("/onboarding/pricing")}>
            Edit Pricing
          </Button>
        </div>
        {summary.pricing.length === 0 ? (
          <p className="text-sm text-muted-foreground">Pricing not configured yet.</p>
        ) : (
          <div className="space-y-2">
            {summary.pricing.map((entry) => (
              <div key={entry.facilitySportId} className="space-y-1 text-sm">
                <div className="flex items-center justify-between">
                  <span className="font-medium text-foreground">{entry.sportName}</span>
                  <span className="text-muted-foreground">
                    {entry.defaultAmountMinor === null
                      ? "Not set"
                      : `${formatCurrency(entry.defaultAmountMinor, entry.currency)} ${PRICING_UNIT_LABEL.PER_HOUR}`}
                  </span>
                </div>
                {entry.overrides.map((override) => (
                  <div key={override.playingAreaId} className="flex items-center justify-between pl-4 text-xs">
                    <span className="text-muted-foreground">{override.playingAreaName}</span>
                    <span className="text-muted-foreground">
                      {formatCurrency(override.amountMinor, entry.currency)} {PRICING_UNIT_LABEL.PER_HOUR}
                    </span>
                  </div>
                ))}
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Setup status */}
      <Card className={`space-y-3 p-5 ${isReady ? "" : "border-amber-500/50"}`}>
        {isReady ? (
          <p className="flex items-center gap-2 text-sm font-medium text-primary">
            <CheckCircle2 className="h-5 w-5" aria-hidden="true" />
            Ready to manage your facility
          </p>
        ) : (
          <>
            <p className="flex items-center gap-2 text-sm font-medium text-amber-600">
              <AlertTriangle className="h-5 w-5" aria-hidden="true" />
              Your setup needs attention
            </p>
            <ul className="space-y-2">
              {summary.missingRequirements.map((req, index) => (
                <li key={`${req.code}-${index}`} className="flex items-center justify-between gap-3 text-sm">
                  <span className="text-muted-foreground">⚠ {req.message}</span>
                  <Button type="button" variant="outline" size="sm" className="h-9 shrink-0 px-2 text-xs" onClick={() => router.push(req.actionHref)}>
                    {req.actionLabel}
                  </Button>
                </li>
              ))}
            </ul>
          </>
        )}
      </Card>

      <div className="flex justify-end">
        <SubmitButton
          type="button"
          onClick={handleComplete}
          pending={isCompleting}
          disabled={!isReady}
          pendingLabel="Completing Setup…"
          className="w-auto sm:min-w-[12rem]"
        >
          Complete Setup →
        </SubmitButton>
      </div>
    </div>
  );
}