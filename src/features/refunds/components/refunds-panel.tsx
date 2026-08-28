"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { formatCurrency } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getRefundService } from "@/services/refunds";
import type { Refund, RefundStatus, SettlementException } from "@/features/refunds/types";
import type { PaymentSourceType } from "@/features/payments/types";
import { ServiceError } from "@/services/shared/service-error";

function refundStatusTone(status: Refund["status"]): "success" | "warning" | "destructive" | "secondary" {
  switch (status) {
    case "PROCESSED":
      return "success";
    case "FAILED":
    case "CANCELLED":
      return "destructive";
    case "REQUESTED":
    case "PROCESSING":
    case "PENDING":
      return "warning";
  }
}

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit", hour12: true });
}

/**
 * Owner-facing refund visibility (spec §13/§28/§29/§30): open settlement
 * exceptions (payment received, business operation not confirmed — spec
 * §16) with a one-click "Initiate Refund", plus the facility's refund
 * history. Every refund shown here is server-authoritative — this page
 * never lets the owner type in a refund amount for a settlement exception
 * (the server always refunds the full captured amount for those).
 */
export function RefundsPanel() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [exceptions, setExceptions] = useState<SettlementException[]>([]);
  const [refunds, setRefunds] = useState<Refund[]>([]);
  const [workingId, setWorkingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [exceptionStatus, setExceptionStatus] = useState<"OPEN" | "RESOLVED" | "ALL">("OPEN");
  const [refundStatus, setRefundStatus] = useState<RefundStatus | "ALL">("ALL");
  const [refundSource, setRefundSource] = useState<PaymentSourceType | "ALL">("ALL");

  async function reload(id: string) {
    const [openExceptions, refundList] = await Promise.all([
      getRefundService().listSettlementExceptions(id, { status: exceptionStatus === "ALL" ? null : exceptionStatus }),
      getRefundService().listRefunds(id, { status: refundStatus === "ALL" ? undefined : refundStatus, sourceType: refundSource === "ALL" ? undefined : refundSource }),
    ]);
    setExceptions(openExceptions);
    setRefunds(refundList);
  }

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const facility = await getFacilityService().getFacility();
      if (cancelled) return;
      if (!facility) {
        setLoadState("none");
        return;
      }
      setFacilityId(facility.id);
      await reload(facility.id);
      if (cancelled) return;
      setLoadState("ready");
    })().catch(() => setLoadState("error"));
    return () => {
      cancelled = true;
    };
    // Filters intentionally excluded here — the below effect handles refetching on filter change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!facilityId || loadState !== "ready") return;
    reload(facilityId).catch(() => setError("Unable to load refunds right now."));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [exceptionStatus, refundStatus, refundSource]);

  async function refundException(exceptionId: string) {
    if (!facilityId) return;
    setWorkingId(exceptionId);
    setError(null);
    try {
      await getRefundService().initiateRefund({ settlementExceptionId: exceptionId });
      await reload(facilityId);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to initiate this refund.");
    } finally {
      setWorkingId(null);
    }
  }

  if (loadState === "loading") return <Skeleton className="h-48 w-full rounded-lg" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load refunds right now.</p>;

  return (
    <div className="space-y-6">
      {error && <p className="text-sm text-destructive">{error}</p>}

      <div>
        <div className="mb-2 flex items-center justify-between gap-2">
          <h2 className="text-sm font-medium">Payment Received, Not Confirmed</h2>
          <Select value={exceptionStatus} onValueChange={(v) => setExceptionStatus(v as typeof exceptionStatus)}>
            <SelectTrigger className="w-[130px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="OPEN">Open</SelectItem>
              <SelectItem value="RESOLVED">Resolved</SelectItem>
              <SelectItem value="ALL">All</SelectItem>
            </SelectContent>
          </Select>
        </div>
        {exceptions.length === 0 ? (
          <p className="text-sm text-muted-foreground">No open settlement exceptions.</p>
        ) : (
          <div className="space-y-2">
            {exceptions.map((ex) => (
              <div key={ex.id} className="flex items-center justify-between rounded-md border border-border p-3 text-sm">
                <div>
                  <p className="font-medium">{ex.sourceType.replace("_", " ")}</p>
                  <p className="text-xs text-muted-foreground">
                    {ex.reason.replace(/_/g, " ").toLowerCase()} · {formatDateTime(ex.createdAt)}
                  </p>
                </div>
                <Button type="button" size="sm" variant="outline" disabled={workingId === ex.id} onClick={() => refundException(ex.id)}>
                  {workingId === ex.id ? "Refunding…" : "Initiate Refund"}
                </Button>
              </div>
            ))}
          </div>
        )}
      </div>

      <div>
        <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-medium">Refund History</h2>
          <div className="flex gap-2">
            <Select value={refundSource} onValueChange={(v) => setRefundSource(v as typeof refundSource)}>
              <SelectTrigger className="w-[150px]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">All Sources</SelectItem>
                <SelectItem value="MEMBERSHIP">Membership</SelectItem>
                <SelectItem value="MEMBER_BOOKING">Member Booking</SelectItem>
                <SelectItem value="GUEST_BOOKING">Guest Booking</SelectItem>
              </SelectContent>
            </Select>
            <Select value={refundStatus} onValueChange={(v) => setRefundStatus(v as typeof refundStatus)}>
              <SelectTrigger className="w-[140px]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">All Status</SelectItem>
                <SelectItem value="PROCESSING">Processing</SelectItem>
                <SelectItem value="PENDING">Pending</SelectItem>
                <SelectItem value="PROCESSED">Processed</SelectItem>
                <SelectItem value="FAILED">Failed</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        {refunds.length === 0 ? (
          <p className="text-sm text-muted-foreground">No refunds yet.</p>
        ) : (
          <div className="max-h-96 space-y-2 overflow-y-auto">
            {refunds.map((r) => (
              <div key={r.id} className="flex items-center justify-between rounded-md border border-border p-3 text-sm">
                <div>
                  <p className="font-medium">
                    {r.sourceType.replace("_", " ")} · {formatCurrency(r.amountMinor, r.currency)}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {r.reason.replace(/_/g, " ").toLowerCase()} · {formatDateTime(r.createdAt)}
                    {r.policyPercentApplied !== null && ` · ${r.policyPercentApplied}% policy`}
                  </p>
                </div>
                <Badge variant={refundStatusTone(r.status)} className="capitalize">
                  {r.status.toLowerCase()}
                </Badge>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}