import { Skeleton } from "@/components/ui/skeleton";

/** Mirrors `AddMemberWizardPage`'s own `facilityLoading` branch. */
export default function AddMemberLoading() {
  return (
    <div className="space-y-5">
      <Skeleton className="h-24 w-full rounded-2xl" />
      <Skeleton className="h-20 w-full rounded-xl" />
      <Skeleton className="h-96 w-full rounded-xl" />
    </div>
  );
}
