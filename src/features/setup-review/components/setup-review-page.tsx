"use client";

import { useRouter } from "next/navigation";
import { Skeleton } from "@/components/ui/skeleton";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { SetupReviewGate } from "@/features/setup-review/components/setup-review-gate";

/** /onboarding/review: where "Complete Setup" lands. Shows the Under Review page, with a way on to the dashboard. */
export function SetupReviewPage() {
  const router = useRouter();
  const { data: user } = useCurrentUser();
  const { data: facility, isLoading } = useFacility();

  if (isLoading) return <Skeleton className="h-[100dvh] w-full" />;
  if (!facility) {
    router.replace("/onboarding/facility");
    return null;
  }
  return <SetupReviewGate facilityId={facility.id} facilityName={facility.name} initialStatus="PENDING" initialNote={null} isOwner={facility.ownerId === user?.id} />;
}
