import { Skeleton } from "@/components/ui/skeleton";

/**
 * Global fallback: Next.js shows this for any route-segment transition
 * (including routes added later) that doesn't define its own more specific
 * loading.tsx. Nested loading.tsx files (e.g. (dashboard)/loading.tsx)
 * take priority for their own subtree, so this rarely renders in practice.
 */
export default function RootLoading() {
  return (
    <div className="flex min-h-[100dvh] items-center justify-center bg-background p-6">
      <div className="w-full max-w-sm space-y-4">
        <Skeleton className="mx-auto h-8 w-32" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-2/3" />
      </div>
    </div>
  );
}
