"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembershipService } from "@/services/memberships";
import type { MembershipPlan } from "@/features/memberships/types";
import { ServiceError } from "@/services/shared/service-error";

function formatRupees(priceInr: number): string {
  return `₹${priceInr.toLocaleString("en-IN")}`;
}

/** Facility-scoped membership plan management — plans are never hard-coded, each facility manages its own list. */
export function MembershipPlansDialog({
  open,
  onOpenChange,
  facilityId,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
}) {
  const [plans, setPlans] = useState<MembershipPlan[] | null>(null);
  const [name, setName] = useState("");
  const [priceInr, setPriceInr] = useState("");
  const [durationDays, setDurationDays] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reload() {
    getMembershipService()
      .getFacilityPlans(facilityId)
      .then((result) => setPlans(result))
      .catch(() => setPlans([]));
  }

  useEffect(() => {
    if (!open) return;
    setPlans(null);
    setName("");
    setPriceInr("");
    setDurationDays("");
    setError(null);
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, facilityId]);

  async function addPlan() {
    const price = Number(priceInr);
    const duration = Number(durationDays);
    if (name.trim().length < 2) {
      setError("Enter a plan name.");
      return;
    }
    if (!Number.isFinite(price) || price < 0) {
      setError("Enter a valid price.");
      return;
    }
    if (!Number.isInteger(duration) || duration <= 0) {
      setError("Enter a valid duration in days.");
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      await getMembershipService().createPlan({ facilityId, name: name.trim(), priceInr: price, durationDays: duration });
      setName("");
      setPriceInr("");
      setDurationDays("");
      reload();
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to save this plan.");
    } finally {
      setIsSaving(false);
    }
  }

  async function toggleActive(plan: MembershipPlan) {
    await getMembershipService().updatePlan(plan.id, { isActive: !plan.isActive });
    reload();
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Membership Plans</DialogTitle>
          <DialogDescription>Manage the plans members can be assigned at this facility.</DialogDescription>
        </DialogHeader>

        {plans === null ? (
          <Skeleton className="h-40 w-full rounded-lg" />
        ) : (
          <div className="space-y-4">
            {plans.length === 0 ? (
              <p className="text-sm text-muted-foreground">No plans yet — add the first one below.</p>
            ) : (
              <div className="divide-y rounded-md border border-border">
                {plans.map((plan) => (
                  <div key={plan.id} className="flex items-center justify-between p-3 text-sm">
                    <div>
                      <p className="font-medium">{plan.name}</p>
                      <p className="text-muted-foreground">
                        {formatRupees(plan.priceInr)} · {plan.durationDays} days
                      </p>
                    </div>
                    <Button type="button" variant="outline" size="sm" onClick={() => toggleActive(plan)}>
                      {plan.isActive ? "Deactivate" : "Activate"}
                    </Button>
                  </div>
                ))}
              </div>
            )}

            <div className="space-y-2 rounded-md border border-dashed border-border p-3">
              <p className="text-sm font-medium">Add a plan</p>
              <input
                aria-label="Plan name"
                placeholder="e.g. Monthly, Quarterly, Annual"
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
              />
              <div className="grid grid-cols-2 gap-2">
                <input
                  aria-label="Price (INR)"
                  placeholder="Price (₹)"
                  inputMode="numeric"
                  value={priceInr}
                  onChange={(e) => setPriceInr(e.target.value)}
                  className="h-10 rounded-md border border-input bg-secondary/60 px-3 text-sm"
                />
                <input
                  aria-label="Duration (days)"
                  placeholder="Duration (days)"
                  inputMode="numeric"
                  value={durationDays}
                  onChange={(e) => setDurationDays(e.target.value)}
                  className="h-10 rounded-md border border-input bg-secondary/60 px-3 text-sm"
                />
              </div>
              {error && <p className="text-sm text-destructive">{error}</p>}
              <Button type="button" size="sm" onClick={addPlan} disabled={isSaving}>
                {isSaving ? "Saving…" : "Add Plan"}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}