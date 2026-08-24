"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembershipService } from "@/services/memberships";
import { computeMembershipEndDate } from "@/features/memberships/status";
import type { Membership, MembershipPlan } from "@/features/memberships/types";
import { ServiceError } from "@/services/shared/service-error";

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function formatRupees(priceInr: number): string {
  return `₹${priceInr.toLocaleString("en-IN")}`;
}

/** Assign a plan to a member, or renew (same write path — a new start date always inserts a new membership row, never overwrites history). */
export function AssignMembershipDialog({
  open,
  onOpenChange,
  facilityId,
  memberId,
  memberName,
  onAssigned,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  memberId: string;
  memberName: string;
  onAssigned: (membership: Membership) => void;
}) {
  const [plans, setPlans] = useState<MembershipPlan[] | null>(null);
  const [planId, setPlanId] = useState("");
  const [startDate, setStartDate] = useState(todayIso());
  const [paymentPaid, setPaymentPaid] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setPlanId("");
    setStartDate(todayIso());
    setPaymentPaid(true);
    setError(null);
    setPlans(null);
    getMembershipService()
      .getFacilityPlans(facilityId, { activeOnly: true })
      .then((result) => setPlans(result))
      .catch(() => setPlans([]));
  }, [open, facilityId]);

  const selectedPlan = plans?.find((p) => p.id === planId) ?? null;
  const endDate = selectedPlan ? computeMembershipEndDate(startDate, selectedPlan.durationDays) : null;

  async function confirm() {
    if (!selectedPlan) {
      setError("Select a membership plan.");
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      const membership = await getMembershipService().createMembership({
        memberId,
        facilityId,
        planId: selectedPlan.id,
        startDate,
        paymentStatus: paymentPaid ? "paid" : "created",
      });
      onAssigned(membership);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to assign this membership.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Assign Membership</DialogTitle>
          <DialogDescription>{memberName}</DialogDescription>
        </DialogHeader>

        {plans === null ? (
          <Skeleton className="h-40 w-full rounded-lg" />
        ) : plans.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No membership plans have been set up for this facility yet. Add a plan first.
          </p>
        ) : (
          <div className="space-y-4">
            <div className="space-y-2">
              <p className="text-sm font-medium">Plan</p>
              <div className="space-y-2">
                {plans.map((plan) => (
                  <button
                    key={plan.id}
                    type="button"
                    onClick={() => setPlanId(plan.id)}
                    className={`flex w-full items-center justify-between rounded-md border px-3 py-2 text-left text-sm ${
                      planId === plan.id ? "border-primary bg-primary/5" : "border-input bg-secondary/60 hover:bg-accent"
                    }`}
                  >
                    <span>
                      {plan.name}
                      <span className="text-muted-foreground"> · {plan.durationDays} days</span>
                    </span>
                    <span className="font-medium">{formatRupees(plan.priceInr)}</span>
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-2">
              <p className="text-sm font-medium">Start date</p>
              <input
                aria-label="Start date"
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="h-11 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
              />
            </div>

            {endDate && (
              <div className="rounded-md bg-secondary/50 p-3 text-sm">
                Ends <span className="font-medium">{new Date(endDate).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}</span>
                {selectedPlan && <span className="text-muted-foreground"> · {formatRupees(selectedPlan.priceInr)}</span>}
              </div>
            )}

            <div>
              <p className="mb-1 text-sm font-medium">Payment</p>
              <div className="flex gap-2">
                <Button type="button" variant={paymentPaid ? "default" : "outline"} size="sm" onClick={() => setPaymentPaid(true)}>
                  Paid
                </Button>
                <Button type="button" variant={!paymentPaid ? "default" : "outline"} size="sm" onClick={() => setPaymentPaid(false)}>
                  Pending
                </Button>
              </div>
            </div>

            {error && <p className="text-sm text-destructive">{error}</p>}
          </div>
        )}

        <DialogFooter>
          <Button type="button" onClick={confirm} disabled={!planId || isSaving}>
            {isSaving ? "Saving…" : "Confirm"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}