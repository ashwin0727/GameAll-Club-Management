"use client";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TimeSelect } from "@/features/operating-hours/components/time-select";
import { DAY_LABELS } from "@/features/operating-hours/types";
import type { OperatingDay, OperatingTimeSlot } from "@/features/operating-hours/types";
import { isOvernightSlot } from "@/features/operating-hours/validation";
import { cn } from "@/lib/utils";

function withComputedOvernight(slot: OperatingTimeSlot): OperatingTimeSlot {
  return { ...slot, crossesMidnight: isOvernightSlot(slot) };
}

export function DayScheduleCard({
  day,
  error,
  onChange,
  onCopyRequest,
  showCopy = true,
}: {
  day: OperatingDay;
  error?: string;
  onChange: (day: OperatingDay) => void;
  onCopyRequest: () => void;
  showCopy?: boolean;
}) {
  function setOpen(open: boolean) {
    if (!open) {
      onChange({ ...day, isClosed: true });
      return;
    }
    onChange({
      ...day,
      isClosed: false,
      slots: day.slots.length > 0 ? day.slots : [{ startTime: "06:00", endTime: "23:00", crossesMidnight: false, displayOrder: 0 }],
    });
  }

  function set24Hours(value: boolean) {
    onChange({ ...day, is24Hours: value, isClosed: false });
  }

  function updateSlot(index: number, patch: Partial<OperatingTimeSlot>) {
    const slots = day.slots.map((slot, i) => (i === index ? withComputedOvernight({ ...slot, ...patch }) : slot));
    onChange({ ...day, slots });
  }

  function addSlot() {
    const last = day.slots[day.slots.length - 1];
    const next: OperatingTimeSlot = {
      startTime: last?.endTime ?? "06:00",
      endTime: "23:00",
      crossesMidnight: false,
      displayOrder: day.slots.length,
    };
    onChange({ ...day, slots: [...day.slots, withComputedOvernight(next)] });
  }

  function removeSlot(index: number) {
    if (day.slots.length <= 1) return;
    onChange({ ...day, slots: day.slots.filter((_, i) => i !== index) });
  }

  const isOpen = !day.isClosed;

  return (
    <Card className="space-y-4 p-4 sm:p-5">
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-sm font-semibold">{DAY_LABELS[day.dayOfWeek]}</h3>
        <div className="flex items-center gap-2">
          {isOpen && showCopy && (
            <Button type="button" variant="ghost" size="sm" className="h-8 px-2 text-xs" onClick={onCopyRequest}>
              Copy hours
            </Button>
          )}
          <button
            type="button"
            role="switch"
            aria-checked={isOpen}
            aria-label={`${DAY_LABELS[day.dayOfWeek]} is ${isOpen ? "open" : "closed"}`}
            onClick={() => setOpen(!isOpen)}
            className={cn(
              "flex h-11 min-w-[84px] items-center justify-center rounded-md border text-sm font-medium transition-colors",
              isOpen
                ? "border-primary bg-primary/10 text-primary"
                : "border-input bg-secondary/60 text-muted-foreground",
            )}
          >
            {isOpen ? "Open" : "Closed"}
          </button>
        </div>
      </div>

      {isOpen && (
        <>
          <button
            type="button"
            role="checkbox"
            aria-checked={day.is24Hours}
            aria-label="Open 24 hours"
            onClick={() => set24Hours(!day.is24Hours)}
            className="flex h-11 items-center gap-2 text-sm"
          >
            <span
              className={cn(
                "flex h-5 w-5 items-center justify-center rounded border",
                day.is24Hours ? "border-primary bg-primary text-primary-foreground" : "border-input",
              )}
            >
              {day.is24Hours ? "✓" : ""}
            </span>
            Open 24 hours
          </button>

          {!day.is24Hours && (
            <div className="space-y-3">
              {day.slots.map((slot, index) => (
                <div key={index} className="space-y-2 rounded-lg border border-border p-3">
                  <div className="grid grid-cols-2 gap-3">
                    <div className="space-y-1">
                      <label className="text-xs font-medium text-muted-foreground">Opens</label>
                      <TimeSelect
                        aria-label={`${DAY_LABELS[day.dayOfWeek]} slot ${index + 1} opening time`}
                        value={slot.startTime}
                        onChange={(value) => updateSlot(index, { startTime: value })}
                      />
                    </div>
                    <div className="space-y-1">
                      <label className="text-xs font-medium text-muted-foreground">Closes</label>
                      <TimeSelect
                        aria-label={`${DAY_LABELS[day.dayOfWeek]} slot ${index + 1} closing time`}
                        value={slot.endTime}
                        onChange={(value) => updateSlot(index, { endTime: value })}
                      />
                    </div>
                  </div>
                  {slot.crossesMidnight && (
                    <p className="text-xs text-muted-foreground">Ends the next day.</p>
                  )}
                  {day.slots.length > 1 && (
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="h-9 px-2 text-xs text-destructive"
                      onClick={() => removeSlot(index)}
                    >
                      Remove slot
                    </Button>
                  )}
                </div>
              ))}
              <Button type="button" variant="outline" size="sm" onClick={addSlot}>
                + Add another time slot
              </Button>
            </div>
          )}
        </>
      )}

      {error && <p className="text-sm text-destructive">{error}</p>}
    </Card>
  );
}