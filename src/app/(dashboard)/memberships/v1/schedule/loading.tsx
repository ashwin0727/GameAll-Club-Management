import { Skeleton } from "@/components/ui/skeleton";

/** Mirrors `MemberSchedulePage`'s own `loading` branch (its hero is static, so only the
 *  data-driven part below it needs a placeholder). */
export default function MemberScheduleLoading() {
  return (
    <div className="space-y-4">
      <Skeleton className="h-[120px] w-full rounded-2xl" />
      <Skeleton className="h-96 w-full rounded-xl" />
    </div>
  );
}
