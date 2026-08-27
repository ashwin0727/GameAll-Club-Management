"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getRefundService } from "@/services/refunds";
import { ServiceError } from "@/services/shared/service-error";

/**
 * Membership cancellation — spec §14/§15: deliberately NOT policy/time-
 * driven. The owner explicitly decides the refund amount (full, partial,
 * or none) rather than it being computed automatically, since an active
 * membership isn't tied to a single future start time the way a booking is.
 */
export function CancelMembershipDialog({
  open,
  onOpenChange,
  membershipId,
  planName,
  onCancelled,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  membershipId: string;
  planName: string;
  onCancelled: () => void;
}) {
  const [refundAmountInr, setRefundAmountInr] = useState("");
  const [isWorking, setIsWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refundNote, setRefundNote] = useState<string | null>(null);

  async function confirmCancel() {
    setIsWorking(true);
    setError(null);
    setRefundNote(null);
    try {
      const amountInr = Number(refundAmountInr);
      const refundAmountMinor = refundAmountInr.trim() !== "" && amountInr > 0 ? Math.round(amountInr * 100) : undefined;
      const { refund } = await getRefundService().cancelMembership({
        membershipId,
        reason: "Owner Request",
        refundAmountMinor,
        overrideReason: refundAmountMinor ? "Owner-decided membership cancellation refund" : undefined,
      });
      if (refund) {
        setRefundNote(refund.status === "FAILED" ? "The membership was cancelled, but the refund could not be submitted. Please retry from Refunds." : "Refund submitted — it will show as processed once Razorpay confirms it.");
      }
      onCancelled();
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to cancel this membership.");
    } finally {
      setIsWorking(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Cancel Membership</DialogTitle>
        </DialogHeader>
        <div className="space-y-3 text-sm">
          <p className="text-muted-foreground">{planName}</p>
          <div className="space-y-2">
            <Label htmlFor="refund_amount">Refund amount (optional)</Label>
            <Input
              id="refund_amount"
              type="number"
              min={0}
              step="0.01"
              placeholder="0"
              value={refundAmountInr}
              onChange={(e) => setRefundAmountInr(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">Leave blank for no refund. The server enforces the maximum refundable amount.</p>
          </div>
          {refundNote && <p className="text-muted-foreground">{refundNote}</p>}
          {error && <p className="text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button type="button" variant="ghost" onClick={() => onOpenChange(false)} disabled={isWorking}>
            Back
          </Button>
          <Button type="button" variant="destructive" onClick={confirmCancel} disabled={isWorking}>
            {isWorking ? "Cancelling…" : "Confirm Cancellation"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}