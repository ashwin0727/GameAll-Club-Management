"use client";

import { useRouter } from "next/navigation";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PlanPicker } from "@/features/plans/components/plan-picker";
import { PlanNotice } from "@/features/plans/components/plan-notice";
import { useMyPlan } from "@/features/plans/hooks";
import { formatRupees } from "@/features/plans/plans";
import { formatPlanDate } from "@/features/profile/plan";

/** Dashboard → Plans. The owner can pick or switch; everyone else sees what the club is on. */
export function PlansPage() {
  const router = useRouter();
  const ctx = usePermissionContext();
  const isOwner = ctx?.baseRole === "owner";
  const mine = useMyPlan(ctx?.facilityId);
  const plan = mine.data ?? null;

  if (!ctx) return null;
  if (mine.isLoading) return <Skeleton className="h-80 w-full rounded-xl" />;

  return (
    <div className="mx-auto max-w-4xl space-y-8 p-4 sm:p-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Plans</h1>
        <p className="mt-1 text-sm text-muted-foreground">What your club is on, and what each plan includes.</p>
      </div>

      <PlanNotice plan={plan} />

      {plan && (
        <Card className="flex flex-wrap items-center justify-between gap-3 p-5">
          <div>
            <p className="text-sm text-muted-foreground">Current plan</p>
            <p className="text-lg font-semibold">
              {plan.name}
              {plan.onTrial ? " · free trial" : ""}
            </p>
          </div>
          <div className="text-right text-sm">
            <p>
              {formatRupees(plan.priceMinor)} / {plan.interval}
            </p>
            <p className="text-muted-foreground">
              {plan.lapsed ? "Ended" : plan.onTrial ? "Trial ends" : "Valid till"} {formatPlanDate(plan.validTill)}
            </p>
          </div>
        </Card>
      )}

      {isOwner ? (
        <PlanPicker facilityId={ctx.facilityId} current={plan} onSelected={() => router.refresh()} />
      ) : (
        <p className="text-sm text-muted-foreground">Only the owner can change the plan.</p>
      )}
    </div>
  );
}
