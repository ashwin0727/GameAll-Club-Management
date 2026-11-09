"use client";

import { useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { formatCurrency } from "@/features/pricing/money";
import type { OfflineRefundDue } from "@/features/refunds/types";
import { getRefundService } from "@/services/refunds";
import { ServiceError } from "@/services/shared/service-error";

/**
 * Cash the club took at the desk for a booking that was then cancelled. Razorpay can only refund what it received, so this part is
 * handed back by the club itself: the cancel screen records the amount, and this list closes it once the cash is returned.
 */
export function CashRefundsDue({ facilityId }: { facilityId: string }) {
  const [items, setItems] = useState<OfflineRefundDue[] | null>(null);
  const [workingId, setWorkingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setItems(await getRefundService().listOfflineRefundsDue(facilityId));
  }, [facilityId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function settle(bookingId: string) {
    setWorkingId(bookingId);
    setError(null);
    try {
      await getRefundService().settleOfflineRefund(bookingId);
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Couldn't update this refund. Please try again.");
    } finally {
      setWorkingId(null);
    }
  }

  if (!items || items.length === 0) return null;

  return (
    <section aria-label="Cash refunds due" data-testid="cash-refunds-due">
      <h2 className="mb-2 text-sm font-medium">Cash Refunds Due at the Club</h2>
      <p className="mb-2 text-xs text-muted-foreground">
        These bookings were paid in cash (or recorded at the desk) and then cancelled. Hand the cash back, then mark it as done.
      </p>
      {error && <p className="mb-2 text-sm text-destructive">{error}</p>}
      <ul className="divide-y divide-border rounded-lg border border-border">
        {items.map((it) => (
          <li key={it.bookingId} className="flex flex-wrap items-center justify-between gap-3 p-3 text-sm">
            <div>
              <p className="font-medium">{it.guestName ?? "Guest"}</p>
              <p className="text-xs text-muted-foreground">
                {it.guestPhone ?? ""} · booking on {new Date(it.startTime).toLocaleDateString("en-IN", { day: "numeric", month: "short" })} · cancelled{" "}
                {new Date(it.cancelledAt).toLocaleDateString("en-IN", { day: "numeric", month: "short" })}
              </p>
            </div>
            <div className="flex items-center gap-3">
              <span className="font-semibold">{formatCurrency(it.refundDueMinor, "INR")}</span>
              <Button type="button" size="sm" variant="outline" disabled={workingId === it.bookingId} onClick={() => void settle(it.bookingId)}>
                {workingId === it.bookingId ? "Saving…" : "Mark handed back"}
              </Button>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
