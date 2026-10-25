import Link from "next/link";
import { cn } from "@/lib/utils";
import { planNotice } from "@/features/plans/plans";
import type { PlanSnapshot } from "@/features/plans/types";

/** One-line banner: no plan yet, trial days left, or lapsed. Renders nothing when the plan needs no attention. */
export function PlanNotice({ plan, link = false }: { plan: PlanSnapshot | null; link?: boolean }) {
  const notice = planNotice(plan);
  if (!notice) return null;
  return (
    <div
      role="status"
      className={cn(
        "flex flex-wrap items-center justify-between gap-2 rounded-lg border px-4 py-2.5 text-sm",
        notice.tone === "warn" ? "border-warning/40 bg-warning/10 text-foreground" : "border-primary/30 bg-primary/5 text-foreground",
      )}
    >
      <span>{notice.text}</span>
      {link && (
        <Link href="/plans" className="font-medium text-primary underline-offset-4 hover:underline">
          {plan ? "View plans" : "Choose a plan"}
        </Link>
      )}
    </div>
  );
}
