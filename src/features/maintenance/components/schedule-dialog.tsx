"use client";

import { useEffect, useState } from "react";
import { AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import type { AffectedBooking } from "@/features/maintenance/types";
import { getMaintenanceService } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

function toLocalInputValue(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function ScheduleDialog({
  open,
  onOpenChange,
  ticketId,
  courtId,
  onScheduled,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  ticketId: string;
  courtId: string;
  onScheduled: () => void;
}) {
  const [start, setStart] = useState(toLocalInputValue(new Date(Date.now() + 60 * 60 * 1000)));
  const [end, setEnd] = useState(toLocalInputValue(new Date(Date.now() + 4 * 60 * 60 * 1000)));
  const [affected, setAffected] = useState<AffectedBooking[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setError(null);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const s = new Date(start);
    const e = new Date(end);
    if (e <= s) {
      setAffected([]);
      return;
    }
    getMaintenanceService()
      .detectAffectedBookings(courtId, s.toISOString(), e.toISOString(), ticketId)
      .then(setAffected)
      .catch(() => setAffected([]));
  }, [open, courtId, ticketId, start, end]);

  async function handleSave() {
    const s = new Date(start);
    const e = new Date(end);
    if (e <= s) {
      setError("End must be after start.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await getMaintenanceService().scheduleMaintenance(ticketId, s.toISOString(), e.toISOString());
      onOpenChange(false);
      onScheduled();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to schedule maintenance.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Schedule Maintenance</DialogTitle>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="space-y-1">
            <span className="text-xs text-muted-foreground">Start</span>
            <Input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
          </label>
          <label className="space-y-1">
            <span className="text-xs text-muted-foreground">End</span>
            <Input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} />
          </label>
        </div>
        {affected.length > 0 && (
          <div className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
            <p>{affected.length} existing booking(s) overlap this window. They will not be cancelled automatically.</p>
          </div>
        )}
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={saving}>
            {saving ? "Saving…" : "Block Court"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
