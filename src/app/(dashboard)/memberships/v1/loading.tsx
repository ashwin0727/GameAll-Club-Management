import { Skeleton } from "@/components/ui/skeleton";

/**
 * Instant fallback for the Membership Dashboard while its server-side auth check and the page's
 * own client bundle/data load — mirrors `MembershipDashboardPage`'s own `facilityLoading` branch
 * so there's no visual jump once the real page takes over.
 */
export default function MembershipDashboardLoading() {
  return (
    <div className="space-y-6">
      <Skeleton className="h-16 w-full rounded-xl" />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 rounded-xl" />
        ))}
      </div>
      <Skeleton className="h-96 w-full rounded-xl" />
    </div>
  );
}
