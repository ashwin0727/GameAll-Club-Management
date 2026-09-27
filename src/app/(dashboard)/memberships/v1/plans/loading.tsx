import { Skeleton } from "@/components/ui/skeleton";

/** Mirrors `MembershipPlansPage`'s own `facilityLoading` branch. */
export default function MembershipPlansLoading() {
  return (
    <div className="space-y-6">
      <Skeleton className="h-24 w-full rounded-2xl" />
      <Skeleton className="h-28 w-full rounded-xl" />
      <Skeleton className="h-96 w-full rounded-xl" />
    </div>
  );
}
