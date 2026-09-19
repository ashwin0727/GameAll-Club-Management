import { Skeleton } from "@/components/ui/skeleton";

/**
 * Renders inside onboarding/layout.tsx's shell (Back button + progress bar
 * stay visible) while a step's page is loading — covers /facility, /sports,
 * /courts, and any future onboarding step automatically. Every step is a form
 * made of a few card sections, so that's what this approximates instead of a
 * spinner.
 */
export default function OnboardingLoading() {
  return (
    <div className="space-y-8">
      {Array.from({ length: 2 }).map((_, i) => (
        <div key={i} className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
          <Skeleton className="h-4 w-32" />
          <div className="grid gap-4 sm:grid-cols-2">
            <Skeleton className="h-11 w-full rounded-lg" />
            <Skeleton className="h-11 w-full rounded-lg" />
          </div>
        </div>
      ))}
      <div className="flex justify-end">
        <Skeleton className="h-11 w-40 rounded-lg" />
      </div>
    </div>
  );
}
