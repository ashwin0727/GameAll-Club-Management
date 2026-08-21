import { LoadingSpinner } from "@/components/shared/loading-state";

/**
 * Global fallback: Next.js shows this for any route-segment transition
 * (including routes added later) that doesn't define its own more specific
 * loading.tsx. Nested loading.tsx files (e.g. (dashboard)/loading.tsx)
 * take priority for their own subtree.
 */
export default function RootLoading() {
  return <LoadingSpinner className="min-h-[100dvh]" />;
}