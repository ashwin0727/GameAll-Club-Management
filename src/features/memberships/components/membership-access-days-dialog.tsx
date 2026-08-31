"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { getMembershipService } from "@/services/memberships";
import { ServiceError } from "@/services/shared/service-error";
import { ALL_DAYS, WEEKDAYS, DAY_OPTIONS, sameDays } from "@/features/memberships/slot-form";

export function MembershipAccessDaysDialog({
  open,
  onOpenChange,
  facilityId,
  currentDays,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  currentDays: number[];
  onSaved: (days: number[]) => void;
}) {
  const [days, setDays] = useState<number[]>(currentDays);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setDays(currentDays);
      setError(null);
    }
  }, [open, currentDays]);

  function toggle(day: number) {
    setDays((prev) => (prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day]));
  }

  async function save() {
    if (days.length === 0) {
      setError("Select at least one day.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const saved = await getMembershipService().setMembershipAccessDays(facilityId, days);
      onSaved(saved);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save access days.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Membership Access Days</DialogTitle>
          <DialogDescription>
            Which days can members use the court? This pre-fills every new membership&apos;s time slot.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-wrap items-center gap-2">
          {DAY_OPTIONS.map((d) => (
            <button
              key={d.value}
              type="button"
              onClick={() => toggle(d.value)}
              className={`h-9 rounded-md border px-3 text-sm font-medium ${
                days.includes(d.value)
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-input bg-secondary/60"
              }`}
            >
              {d.label}
            </button>
          ))}
          <Button type="button" variant="outline" size="sm" onClick={() => setDays([...ALL_DAYS])}>
            All 7
          </Button>
          <Button type="button" variant="outline" size="sm" onClick={() => setDays([...WEEKDAYS])}>
            Mon–Fri
          </Button>
        </div>

        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button type="button" onClick={save} disabled={saving || sameDays(days, currentDays)}>
            {saving ? "Saving…" : "Save"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}