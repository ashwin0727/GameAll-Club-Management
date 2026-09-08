"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { getMaintenanceService, type FacilityStaffOption } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

export function AssignDialog({
  open,
  onOpenChange,
  ticketId,
  facilityId,
  onAssigned,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  ticketId: string;
  facilityId: string;
  onAssigned: () => void;
}) {
  const [staff, setStaff] = useState<FacilityStaffOption[]>([]);
  const [assignedTo, setAssignedTo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setError(null);
    getMaintenanceService().listAssignableStaff(facilityId).then(setStaff).catch(() => setStaff([]));
  }, [open, facilityId]);

  async function handleSave() {
    if (!assignedTo) {
      setError("Choose a staff member.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await getMaintenanceService().assignTicket(ticketId, assignedTo);
      onOpenChange(false);
      onAssigned();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to assign this ticket.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Assign to Staff</DialogTitle>
        </DialogHeader>
        <select
          value={assignedTo}
          onChange={(e) => setAssignedTo(e.target.value)}
          className="h-11 w-full rounded-lg border border-input bg-background px-3 text-sm"
        >
          <option value="">Select staff member</option>
          {staff.map((s) => (
            <option key={s.userId} value={s.userId}>
              {s.fullName} ({s.role})
            </option>
          ))}
        </select>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={saving}>
            {saving ? "Assigning…" : "Assign"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
