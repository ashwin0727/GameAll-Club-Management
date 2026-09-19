import { Skeleton } from "@/components/ui/skeleton";

/**
 * Generic content-area skeleton shown while a dashboard-area route segment
 * loads (Next.js route-level loading.tsx). One shared loading.tsx covers
 * every page under (dashboard) — it can't know which specific page is
 * loading — so this approximates the shape most of them share (a
 * title/toolbar row, a stat row, then a content block) instead of a
 * content-agnostic spinner.
 */
export function PageSkeleton() {
  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <Skeleton className="h-7 w-40" />
        <Skeleton className="h-9 w-full sm:w-64" />
      </div>
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 rounded-xl" />
        ))}
      </div>
      <Skeleton className="h-96 w-full rounded-xl" />
    </div>
  );
}
