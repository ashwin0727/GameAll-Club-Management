"use client";

import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { TimeField } from "@/features/memberships/components/time-field";
import { DAY_LABELS } from "@/features/coaching/components/shared";
import { findAvailabilityConflict, isValidSlot } from "@/features/coaching/coach-onboarding-validation";
import type { CoachAvailabilityWindow } from "@/features/coaching/types";
import { cn } from "@/lib/utils";

/** Indexes of every window that repeats or overlaps another window on the same day — those rows are outlined in red. */
function conflictingIndexes(windows: CoachAvailabilityWindow[]): Set<number> {
  const bad = new Set<number>();
  windows.forEach((a, i) => {
    windows.forEach((b, j) => {
      if (i >= j || a.dayOfWeek !== b.dayOfWeek) return;
      const [as, ae, bs, be] = [a.startTime.slice(0, 5), a.endTime.slice(0, 5), b.startTime.slice(0, 5), b.endTime.slice(0, 5)];
      if (!isValidSlot(as, ae) || !isValidSlot(bs, be)) return;
      if (as < be && bs < ae) {
        bad.add(i);
        bad.add(j);
      }
    });
  });
  return bad;
}

/**
 * The recurring weekly-windows editor — the list of day/start/end rows plus add/remove. Shared
 * by the Coach Profile's Availability tab (which owns its own save button and the exceptions
 * list below it) and the Add Coach wizard's Availability step. Kept purely controlled so both
 * callers can own their own save/dirty state without this component knowing about either.
 *
 * Each window is its own labelled card (Day / From / To) so nothing sits on a cramped single line, and a repeated or overlapping
 * slot on the same day is flagged straight away, on the rows involved, with a message naming them.
 */
export function CoachAvailabilityEditor({
  windows,
  onChange,
  readOnly = false,
}: {
  windows: CoachAvailabilityWindow[];
  onChange: (next: CoachAvailabilityWindow[]) => void;
  readOnly?: boolean;
}) {
  const conflict = readOnly ? null : findAvailabilityConflict(windows);
  const bad = conflict ? conflictingIndexes(windows) : new Set<number>();

  return (
    <div className="space-y-3">
      {windows.length === 0 && <p className="text-sm text-muted-foreground">No availability set.</p>}
      {windows.map((w, i) => {
        const endBeforeStart = !readOnly && !isValidSlot(w.startTime.slice(0, 5), w.endTime.slice(0, 5));
        return (
          // `focus-within:z-30` lifts the row whose time picker is open above the rows after it, so the dropdown is never painted under them.
          <div
            key={i}
            className={cn(
              "relative grid grid-cols-2 gap-3 rounded-lg border p-3 focus-within:z-30 sm:grid-cols-[9rem_1fr_1fr_auto] sm:items-end",
              bad.has(i) || endBeforeStart ? "border-destructive/60 bg-destructive/5" : "border-border",
            )}
          >
            <div className="col-span-2 space-y-1 sm:col-span-1">
              <span className="text-xs font-medium text-muted-foreground">Day</span>
              <Select
                value={String(w.dayOfWeek)}
                onValueChange={(v) => onChange(windows.map((x, j) => (j === i ? { ...x, dayOfWeek: Number(v) } : x)))}
                disabled={readOnly}
              >
                <SelectTrigger aria-label="Day">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {DAY_LABELS.map((d, di) => (
                    <SelectItem key={di} value={String(di)}>
                      {d}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <span className="text-xs font-medium text-muted-foreground">From</span>
              {readOnly ? (
                <p className="text-sm">{w.startTime.slice(0, 5)}</p>
              ) : (
                <TimeField ariaLabel="Start time" value={w.startTime.slice(0, 5)} onChange={(v) => onChange(windows.map((x, j) => (j === i ? { ...x, startTime: v } : x)))} />
              )}
            </div>
            <div className="space-y-1">
              <span className="text-xs font-medium text-muted-foreground">To</span>
              {readOnly ? (
                <p className="text-sm">{w.endTime.slice(0, 5)}</p>
              ) : (
                <TimeField ariaLabel="End time" value={w.endTime.slice(0, 5)} onChange={(v) => onChange(windows.map((x, j) => (j === i ? { ...x, endTime: v } : x)))} />
              )}
            </div>
            {!readOnly && (
              <Button type="button" variant="ghost" size="icon" className="col-span-2 justify-self-end sm:col-span-1" aria-label="Remove window" onClick={() => onChange(windows.filter((_, j) => j !== i))}>
                <Trash2 className="h-4 w-4" aria-hidden />
              </Button>
            )}
            {endBeforeStart && <p className="col-span-2 text-xs text-destructive sm:col-span-4">The end time must be after the start time.</p>}
          </div>
        );
      })}

      {conflict && (
        <p role="alert" className="text-xs text-destructive">
          {conflict}
        </p>
      )}

      {!readOnly && (
        <Button type="button" variant="outline" size="sm" onClick={() => onChange([...windows, nextWindow(windows)])}>
          <Plus className="h-4 w-4" aria-hidden /> Add Window
        </Button>
      )}
    </div>
  );
}

/** A new window that does not collide with the ones already there: the first day with no window, else the same slot the day after the last. */
function nextWindow(windows: CoachAvailabilityWindow[]): CoachAvailabilityWindow {
  const used = new Set(windows.map((w) => w.dayOfWeek));
  const free = [1, 2, 3, 4, 5, 6, 0].find((d) => !used.has(d));
  if (free !== undefined) return { dayOfWeek: free, startTime: "16:00", endTime: "20:00" };
  const last = windows[windows.length - 1];
  return { dayOfWeek: last ? (last.dayOfWeek + 1) % 7 : 1, startTime: "16:00", endTime: "20:00" };
}

/** Every window's end time must be after its start time and no day may repeat or overlap a slot — shared validation for both callers. */
export function validateAvailabilityWindows(windows: CoachAvailabilityWindow[]): string | null {
  for (const w of windows) {
    if (w.endTime <= w.startTime) return "Every window's end time must be after its start time.";
  }
  return findAvailabilityConflict(windows);
}
