"use client";

import { useRouter } from "next/navigation";
import { Skeleton } from "@/components/ui/skeleton";
import { FormMessage } from "@/features/auth/components/form-message";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import { PlanPicker } from "@/features/plans/components/plan-picker";
import { useMyPlan } from "@/features/plans/hooks";

/** Onboarding step after Payout: pick Basic or Advanced, then on to the setup summary. */
export function OnboardingPlanStep() {
  const router = useRouter();
  const { data: user } = useCurrentUser();
  const { data: facility, isLoading } = useFacility();
  const completePlan = useOnboardingStore((s) => s.completePlan);
  const isOwner = !!facility && facility.ownerId === user?.id;
  const mine = useMyPlan(isOwner ? facility?.id : undefined);

  if (isLoading || (isOwner && mine.isLoading)) return <Skeleton className="h-80 w-full rounded-xl" />;
  if (!facility) {
    router.replace("/onboarding/facility");
    return null;
  }
  if (!isOwner) return <FormMessage>You don&apos;t have access to this facility.</FormMessage>;

  function next() {
    completePlan();
    router.push("/onboarding/complete");
  }

  return (
    <div className="space-y-6">
      <PlanPicker facilityId={facility.id} current={mine.data ?? null} onSelected={next} />
      <div className="text-center">
        <button type="button" onClick={next} className="text-sm text-muted-foreground underline-offset-4 hover:underline">
          Decide later
        </button>
      </div>
    </div>
  );
}
