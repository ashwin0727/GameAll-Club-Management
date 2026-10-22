"use client";

import { useState } from "react";
import { Building2, CalendarDays, Check, Crown, IndianRupee } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { daysLeft, formatPlanDate, INTERVAL_LABEL, isPlanActive } from "@/features/profile/plan";
import type { FacilityPlan } from "@/features/profile/types";
import { formatCurrency } from "@/features/pricing/money";
import { cn } from "@/lib/utils";

function Fact({ icon: Icon, label, value }: { icon: React.ComponentType<{ className?: string }>; label: string; value: string }) {
  return (
    <div className="flex min-w-0 items-center gap-2.5">
      <Icon className="h-5 w-5 shrink-0 text-muted-foreground" aria-hidden />
      <div className="min-w-0">
        <p className="text-[11px] text-muted-foreground">{label}</p>
        <p className="truncate text-sm font-semibold">{value}</p>
      </div>
    </div>
  );
}

/**
 * "Active Membership Plan": GameAll's own plan for this facility. GameAll is paid a membership fee rather than a
 * commission, so this is what the owner is paying for and until when. Past its valid-till date, or once cancelled, the
 * plan reads Inactive.
 */
export function PlanCard({
  plan,
  loading,
  facilityName,
  error,
}: {
  plan: FacilityPlan | null | undefined;
  loading: boolean;
  facilityName: string;
  error?: boolean;
}) {
  const [open, setOpen] = useState(false);

  if (loading) return <Skeleton className="h-44 w-full rounded-xl" />;

  const active = isPlanActive(plan ?? null);
  const left = plan ? daysLeft(plan.validTill) : 0;

  return (
    <Card
      className={cn(
        "relative overflow-hidden p-4 sm:p-5",
        active ? "border-primary/30 bg-gradient-to-br from-primary/10 to-card" : "border-border",
      )}
    >
      <div className="flex items-start gap-3 sm:gap-4">
        <span
          className={cn(
            "flex h-14 w-14 shrink-0 items-center justify-center rounded-full shadow-sm",
            active ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground",
          )}
        >
          <Crown className="h-7 w-7" aria-hidden />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className={cn("text-xs font-medium", active ? "text-primary" : "text-muted-foreground")}>
              {active ? "Active Membership Plan" : "Membership Plan"}
            </p>
            {plan && (
              <Badge variant={active ? "success" : "destructive"} className={active ? "bg-success/15 text-success" : "bg-destructive/15 text-destructive"}>
                {active ? "Active" : "Inactive"}
              </Badge>
            )}
          </div>
          {plan ? (
            <>
              <h2 className="truncate text-xl font-semibold">{plan.planName}</h2>
              <p className="text-sm text-muted-foreground">GameAll Club Management</p>
            </>
          ) : (
            <>
              <h2 className="text-lg font-semibold">{error ? "Plan unavailable" : "No plan yet"}</h2>
              <p className="text-sm text-muted-foreground">
                {error
                  ? "We couldn't load your GameAll plan. Please refresh to try again."
                  : "Your GameAll membership plan will show up here once it is set up for this facility."}
              </p>
            </>
          )}
        </div>
      </div>

      {plan && (
        <>
          <div className="my-4 border-t border-border/70" />
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-[1fr_1fr_1fr_auto] sm:items-center">
            <Fact icon={Building2} label="Facility" value={facilityName} />
            <Fact
              icon={IndianRupee}
              label="Plan Price"
              value={`${formatCurrency(plan.priceMinor, plan.currency)} / ${INTERVAL_LABEL[plan.interval]}`}
            />
            <Fact icon={CalendarDays} label="Valid Till" value={formatPlanDate(plan.validTill)} />
            <Button variant="outline" size="sm" className="col-span-2 sm:col-span-1" onClick={() => setOpen(true)}>
              View Plan Details
            </Button>
          </div>
          {active && left <= 14 && (
            <p className="mt-3 text-xs text-warning-foreground">
              Your plan ends {left === 0 ? "today" : `in ${left} day${left === 1 ? "" : "s"}`}. Contact GameAll to renew it.
            </p>
          )}
          {!active && (
            <p className="mt-3 text-xs text-destructive">
              This plan has {plan.status === "cancelled" ? "been cancelled" : "expired"}. Contact GameAll to renew it.
            </p>
          )}

          <Dialog open={open} onOpenChange={setOpen}>
            <DialogContent className="max-w-md">
              <DialogHeader>
                <DialogTitle>{plan.planName}</DialogTitle>
                <DialogDescription>
                  {formatCurrency(plan.priceMinor, plan.currency)} per {INTERVAL_LABEL[plan.interval]} · valid till{" "}
                  {formatPlanDate(plan.validTill)}
                </DialogDescription>
              </DialogHeader>
              {plan.features.length > 0 ? (
                <ul className="space-y-2 text-sm">
                  {plan.features.map((f) => (
                    <li key={f} className="flex items-start gap-2">
                      <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                      <span>{f}</span>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm text-muted-foreground">The details of this plan haven&apos;t been added yet.</p>
              )}
              <p className="text-xs text-muted-foreground">
                GameAll charges a flat membership fee — never a commission on your bookings or payments.
              </p>
            </DialogContent>
          </Dialog>
        </>
      )}
    </Card>
  );
}
