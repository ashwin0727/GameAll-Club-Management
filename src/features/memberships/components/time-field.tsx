"use client";

import { useEffect, useRef, useState } from "react";
import { ChevronDown, Moon, Sun, Sunrise, Sunset } from "lucide-react";
import { formatClock12 } from "@/features/memberships/components/member-schedule-grid";
import { cn } from "@/lib/utils";

interface Period {
  key: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  /** Minutes since midnight, inclusive. */
  startMin: number;
  /** Minutes since midnight, exclusive — the next period's own startMin, so every half-hour of
   *  the day belongs to exactly one card and no time is offered twice. */
  endMin: number;
}

const PERIODS: Period[] = [
  { key: "morning", label: "Morning", icon: Sunrise, startMin: 0, endMin: 11 * 60 },
  { key: "afternoon", label: "Afternoon", icon: Sun, startMin: 11 * 60, endMin: 16 * 60 },
  { key: "evening", label: "Evening", icon: Sunset, startMin: 16 * 60, endMin: 20 * 60 },
  { key: "night", label: "Night", icon: Moon, startMin: 20 * 60, endMin: 24 * 60 },
];

function toTimeString(totalMin: number): string {
  const h = Math.floor(totalMin / 60) % 24;
  const m = totalMin % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

function toMinutes(value: string): number {
  const [h, m] = value.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

function periodRangeLabel(p: Period): string {
  // endMin lands on 1440 for Night, which is midnight — "12:00 AM", not a nonexistent "24:00".
  return `${formatClock12(toTimeString(p.startMin))} to ${formatClock12(toTimeString(p.endMin % 1440))}`;
}

function periodFor(value: string): Period {
  const min = toMinutes(value);
  return PERIODS.find((p) => min >= p.startMin && min < p.endMin) ?? PERIODS[PERIODS.length - 1]!;
}

/**
 * A time-of-day picker in the same collapsed-card style as a food app's delivery-slot picker:
 * Morning/Afternoon/Evening/Night cards, each collapsed to its own label + time range until
 * tapped open, then showing every half-hour inside it as a chip. Replaces both the browser's
 * native <select> (wrong border radius, doesn't match the app) and an earlier hour/minute-wheel
 * version of this same field — this is the design the owner actually asked for.
 */
export function TimeField({ value, onChange, ariaLabel }: { value: string; onChange: (value: string) => void; ariaLabel: string }) {
  const [open, setOpen] = useState(false);
  const [expanded, setExpanded] = useState<string>(() => periodFor(value).key);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    // Re-open on whichever period the current value actually falls in, each time the picker opens.
    setExpanded(periodFor(value).key);
    function onDocClick(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- re-syncs to `value` only on open
  }, [open]);

  function pick(min: number) {
    onChange(toTimeString(min));
    setOpen(false);
  }

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        aria-label={ariaLabel}
        onClick={() => setOpen((o) => !o)}
        className="flex h-9 items-center gap-1.5 rounded-lg border border-input bg-card px-2 text-sm outline-none transition-colors hover:border-foreground/30"
      >
        {formatClock12(value)}
        <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
      </button>

      {open && (
        // Centered under the trigger and width-clamped to the viewport (minus a 1rem margin each
        // side) rather than anchored hard-left at a fixed 288px — on a narrow phone screen, the
        // End Time field (sitting well right of Start Time in its row) would otherwise push this
        // panel off the right edge instead of just narrowing it.
        <div className="absolute left-1/2 z-50 mt-1 max-h-[360px] w-[min(18rem,calc(100vw-2rem))] -translate-x-1/2 space-y-1.5 overflow-y-auto rounded-lg border border-border bg-popover p-2 shadow-lg">
          {PERIODS.map((p) => {
            const isOpen = expanded === p.key;
            const Icon = p.icon;
            const selectedHere = periodFor(value).key === p.key;
            return (
              <div key={p.key} className="overflow-hidden rounded-lg border border-border">
                <button
                  type="button"
                  onClick={() => setExpanded(isOpen ? "" : p.key)}
                  className={cn("flex w-full items-center gap-2.5 px-2.5 py-2 text-left transition-colors", selectedHere ? "bg-success/5" : "hover:bg-accent/50")}
                >
                  <span
                    className={cn(
                      "flex h-8 w-8 shrink-0 items-center justify-center rounded-full",
                      selectedHere ? "bg-success/15 text-success" : "bg-muted text-muted-foreground",
                    )}
                  >
                    <Icon className="h-4 w-4" aria-hidden />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm font-semibold text-foreground">{p.label}</span>
                    <span className="block text-xs text-muted-foreground">{periodRangeLabel(p)}</span>
                  </span>
                  <ChevronDown className={cn("h-4 w-4 shrink-0 text-muted-foreground transition-transform", isOpen && "rotate-180")} aria-hidden />
                </button>

                {isOpen && (
                  <div className="grid grid-cols-3 gap-1.5 border-t border-border p-2">
                    {Array.from({ length: (p.endMin - p.startMin) / 30 }, (_, i) => p.startMin + i * 30).map((min) => (
                      <button
                        key={min}
                        type="button"
                        onClick={() => pick(min)}
                        className={cn(
                          "whitespace-nowrap rounded-lg border px-1.5 py-1.5 text-center text-[11px] font-medium transition-colors",
                          toMinutes(value) === min ? "border-success bg-success/10 text-success" : "border-input hover:bg-accent/50",
                        )}
                      >
                        {formatClock12(toTimeString(min))}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
