"use client";

import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { toMinorUnits } from "@/features/pricing/money";
import type { RecordMovementInput } from "@/features/inventory/types";

type Mode = "STOCK_IN" | "STOCK_OUT" | "ADJUSTMENT";

const TITLE: Record<Mode, string> = {
  STOCK_IN: "Record Stock In",
  STOCK_OUT: "Record Stock Out",
  ADJUSTMENT: "Adjust Stock",
};

export function RecordMovementDialog({
  open,
  onOpenChange,
  mode,
  itemId,
  itemName,
  currentStock,
  unit,
  onDone,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  mode: Mode;
  itemId: string;
  itemName: string;
  currentStock: number;
  unit: string;
  onDone: () => void;
}) {
  const [qty, setQty] = useState("");
  const [reason, setReason] = useState("");
  const [notes, setNotes] = useState("");
  const [unitCost, setUnitCost] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setQty("");
    setReason("");
    setNotes("");
    setUnitCost("");
    setError(null);
  }

  async function submit() {
    const n = Number(qty);
    if (!Number.isFinite(n) || n <= 0) {
      setError("Enter a quantity greater than zero.");
      return;
    }
    if (mode === "ADJUSTMENT" && !reason.trim()) {
      setError("An adjustment needs a reason.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const payload: RecordMovementInput =
        mode === "ADJUSTMENT"
          ? {
              itemId,
              movementType: "ADJUSTMENT",
              // Adjustment quantity is the delta to the counted total.
              quantity: n - currentStock,
              reason: reason.trim(),
              notes: notes.trim() || null,
            }
          : {
              itemId,
              movementType: mode,
              quantity: mode === "STOCK_OUT" ? -n : n,
              reason: reason.trim() || null,
              notes: notes.trim() || null,
              unitCostMinor:
                mode === "STOCK_IN" && unitCost.trim() ? toMinorUnits(unitCost, "INR") : null,
            };
      await getInventoryService().recordMovement(payload);
      reset();
      onOpenChange(false);
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not record that movement.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(v) => {
        if (!busy) {
          if (!v) reset();
          onOpenChange(v);
        }
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{TITLE[mode]}</DialogTitle>
          <DialogDescription>
            {itemName} · currently {currentStock} {unit} in stock
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="mv-qty">
              {mode === "ADJUSTMENT" ? `Counted quantity (${unit})` : `Quantity (${unit})`}
            </Label>
            <Input
              id="mv-qty"
              type="number"
              min="0"
              step="1"
              value={qty}
              onChange={(e) => setQty(e.target.value)}
            />
          </div>

          {mode === "STOCK_IN" && (
            <div className="space-y-1.5">
              <Label htmlFor="mv-cost">Unit cost (₹, optional)</Label>
              <Input
                id="mv-cost"
                type="number"
                min="0"
                step="0.01"
                value={unitCost}
                onChange={(e) => setUnitCost(e.target.value)}
                placeholder="Updates the weighted-average cost"
              />
            </div>
          )}

          <div className="space-y-1.5">
            <Label htmlFor="mv-reason">Reason{mode === "ADJUSTMENT" ? "" : " (optional)"}</Label>
            <Input id="mv-reason" value={reason} onChange={(e) => setReason(e.target.value)} />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="mv-notes">Notes (optional)</Label>
            <Textarea id="mv-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>

          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" disabled={busy} onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button type="button" disabled={busy} onClick={() => void submit()}>
            {busy ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
