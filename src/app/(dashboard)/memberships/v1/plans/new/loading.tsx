import { Skeleton } from "@/components/ui/skeleton";

/** Mirrors `CreatePlanWizardPage`'s own `facilityLoading` branch. */
export default function CreatePlanLoading() {
  return (
    <div className="space-y-5">
      <Skeleton className="h-[120px] w-full rounded-2xl" />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[280px_1fr]">
        <Skeleton className="h-96 w-full rounded-xl" />
        <Skeleton className="h-96 w-full rounded-xl" />
      </div>
    </div>
  );
}
