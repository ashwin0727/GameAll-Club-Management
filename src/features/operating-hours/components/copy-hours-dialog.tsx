"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { DAYS_OF_WEEK, DAY_LABELS, type DayOfWeek } from "@/features/operating-hours/types";
import { cn } from "@/lib/utils";

const WEEKDAYS: DayOfWeek[] = [1, 2, 3, 4, 5];

export function CopyHoursDialog({
  open,
  onOpenChange,
  fromDay,
  onCopy,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  fromDay: DayOfWeek;
  onCopy: (toDays: DayOfWeek[]) => void;
}) {
  const [selected, setSelected] = useState<DayOfWeek[]>([]);

  function toggle(day: DayOfWeek) {
    setSelected((prev) => (prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day]));
  }

  function handleOpenChange(next: boolean) {
    if (!next) setSelected([]);
    onOpenChange(next);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Copy {DAY_LABELS[fromDay]}&apos;s hours</DialogTitle>
          <DialogDescription>Choose which days should use the same hours.</DialogDescription>
        </DialogHeader>

        <Button
          type="button"
          variant="outline"
          size="sm"
          className="w-fit"
          onClick={() => setSelected(WEEKDAYS.filter((d) => d !== fromDay))}
        >
          Copy to weekdays
        </Button>

        <div className="grid grid-cols-2 gap-2">
          {DAYS_OF_WEEK.filter((d) => d !== fromDay).map((day) => {
            const checked = selected.includes(day);
            return (
              <button
                key={day}
                type="button"
                role="checkbox"
                aria-checked={checked}
                onClick={() => toggle(day)}
                className={cn(
                  "flex h-11 items-center justify-start gap-2 rounded-md border px-3 text-sm",
                  checked ? "border-primary bg-primary/10 text-primary" : "border-input",
                )}
              >
                <span
                  className={cn(
                    "flex h-4 w-4 items-center justify-center rounded border text-[10px]",
                    checked ? "border-primary bg-primary text-primary-foreground" : "border-muted-foreground",
                  )}
                >
                  {checked ? "✓" : ""}
                </span>
                {DAY_LABELS[day]}
              </button>
            );
          })}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
            Cancel
          </Button>
          <Button
            type="button"
            disabled={selected.length === 0}
            onClick={() => {
              onCopy(selected);
              handleOpenChange(false);
            }}
          >
            Copy
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}