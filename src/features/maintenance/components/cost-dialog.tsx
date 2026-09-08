"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getMaintenanceService } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

/** Actual cost posts to the EXISTING Finance/Expenses RPC (create_expense) — never a second ledger. */
export function CostDialog({
  open,
  onOpenChange,
  ticketId,
  currency,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  ticketId: string;
  currency: string;
  onSaved: () => void;
}) {
  const [estimated, setEstimated] = useState("");
  const [actual, setActual] = useState("");
  const [postToExpenses, setPostToExpenses] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  async function handleSave() {
    setSaving(true);
    setError(null);
    try {
      await getMaintenanceService().updateCost({
        ticketId,
        estimatedCostMinor: estimated ? Math.round(Number(estimated) * 100) : null,
        actualCostMinor: actual ? Math.round(Number(actual) * 100) : null,
        postToExpenses,
      });
      onOpenChange(false);
      onSaved();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save cost.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Update Repair Cost</DialogTitle>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label>Estimated Cost ({currency})</Label>
            <Input type="number" min={0} value={estimated} onChange={(e) => setEstimated(e.target.value)} placeholder="Leave blank to keep" />
          </div>
          <div className="space-y-1.5">
            <Label>Actual Cost ({currency})</Label>
            <Input type="number" min={0} value={actual} onChange={(e) => setActual(e.target.value)} placeholder="Leave blank to keep" />
          </div>
        </div>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={postToExpenses} onChange={(e) => setPostToExpenses(e.target.checked)} className="h-4 w-4 rounded border-input" />
          Post actual cost to Finance → Expenses
        </label>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={saving}>
            {saving ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
