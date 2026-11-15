import { CalendarDays, Clock, MapPin } from "lucide-react";
import { DAY_OPTIONS } from "@/features/memberships/slot-form";
import { formatClock } from "@/features/memberships/slot-format";
import type { PlanSlot } from "@/features/memberships/plan-slots";
import { cn } from "@/lib/utils";

/**
 * The court(s) and timings a plan reserves, read-only. They're configured once, when the plan
 * is created, so a member joining it can see them but not change them.
 */
export function PlanSlotsList({
  slots,
  className,
  selectedIds,
  onToggle,
}: {
  slots: PlanSlot[];
  className?: string;
  /** With [onToggle], each timing becomes a tick box and these are the ticked ones. */
  selectedIds?: readonly string[];
  onToggle?: (batchId: string) => void;
}) {
  const selectable = Boolean(onToggle);
  if (slots.length === 0) {
    return <p className="text-xs text-muted-foreground">This plan doesn&apos;t reserve any court time.</p>;
  }
  return (
    <ul className={cn("space-y-2", className)}>
      {slots.map((s) => (
        <li
          key={s.batchId}
          className={cn(
            "space-y-2 rounded-lg border p-3 text-xs",
            selectable && selectedIds?.includes(s.batchId) ? "border-primary bg-primary/5" : "border-border bg-muted/30",
          )}
        >
          <div className="flex items-center gap-1.5 font-semibold text-foreground">
            {selectable && (
              <input
                type="checkbox"
                checked={selectedIds?.includes(s.batchId) ?? false}
                onChange={() => onToggle?.(s.batchId)}
                aria-label={`${s.courtName} ${formatClock(s.startTime)} - ${formatClock(s.endTime)}`}
                className="mr-1 h-4 w-4 shrink-0 cursor-pointer accent-primary"
              />
            )}
            <MapPin className="h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
            {s.courtName}
          </div>
          <div className="flex items-center gap-1.5 text-foreground">
            <Clock className="h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
            {formatClock(s.startTime)} - {formatClock(s.endTime)}
          </div>
          <div className="flex items-start gap-1.5">
            <CalendarDays className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
            <div className="flex flex-wrap gap-1">
              {DAY_OPTIONS.map((d) => (
                <span
                  key={d.value}
                  className={cn(
                    "rounded-md px-2 py-0.5 text-[11px] font-medium",
                    s.daysOfWeek.includes(d.value) ? "bg-[#4817C2] text-white" : "bg-muted text-muted-foreground",
                  )}
                >
                  {d.label}
                </span>
              ))}
            </div>
          </div>
        </li>
      ))}
    </ul>
  );
}
