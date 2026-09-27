"use client";

import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { TimeField } from "@/features/memberships/components/time-field";
import { DAY_LABELS } from "@/features/coaching/components/shared";
import type { CoachAvailabilityWindow } from "@/features/coaching/types";

/**
 * The recurring weekly-windows editor — the list of day/start/end rows plus add/remove. Shared
 * by the Coach Profile's Availability tab (which owns its own save button and the exceptions
 * list below it) and the Add Coach wizard's Availability step (which defers saving to the
 * wizard's final submit). Kept purely controlled so both callers can own their own save/dirty
 * state without this component knowing about either.
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
  return (
    <div className="space-y-2">
      {windows.length === 0 && <p className="text-sm text-muted-foreground">No availability set.</p>}
      {windows.map((w, i) => (
        <div key={i} className="flex flex-wrap items-center gap-2">
          <Select
            value={String(w.dayOfWeek)}
            onValueChange={(v) => onChange(windows.map((x, j) => (j === i ? { ...x, dayOfWeek: Number(v) } : x)))}
            disabled={readOnly}
          >
            <SelectTrigger className="w-[7rem]">
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
          {readOnly ? (
            <span className="text-sm">{w.startTime.slice(0, 5)}</span>
          ) : (
            <TimeField
              ariaLabel="Start time"
              value={w.startTime.slice(0, 5)}
              onChange={(v) => onChange(windows.map((x, j) => (j === i ? { ...x, startTime: v } : x)))}
            />
          )}
          <span className="text-muted-foreground">–</span>
          {readOnly ? (
            <span className="text-sm">{w.endTime.slice(0, 5)}</span>
          ) : (
            <TimeField
              ariaLabel="End time"
              value={w.endTime.slice(0, 5)}
              onChange={(v) => onChange(windows.map((x, j) => (j === i ? { ...x, endTime: v } : x)))}
            />
          )}
          {!readOnly && (
            <Button variant="ghost" size="sm" onClick={() => onChange(windows.filter((_, j) => j !== i))}>
              Remove
            </Button>
          )}
        </div>
      ))}

      {!readOnly && (
        <Button
          variant="outline"
          size="sm"
          onClick={() => onChange([...windows, { dayOfWeek: 1, startTime: "16:00", endTime: "20:00" }])}
        >
          Add window
        </Button>
      )}
    </div>
  );
}

/** Every window's end time must be after its start time — shared validation for both callers. */
export function validateAvailabilityWindows(windows: CoachAvailabilityWindow[]): string | null {
  for (const w of windows) {
    if (w.endTime <= w.startTime) return "Every window's end time must be after its start time.";
  }
  return null;
}
