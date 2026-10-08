"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Check, Copy, Link2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import type { BillingStatus, EnrollmentBilling } from "@/features/coaching/types";
import { fmtDate, money } from "@/features/coaching/components/shared";

const STATUS_LABEL: Record<BillingStatus, string> = {
  CREATED: "Awaiting payment",
  AUTHENTICATED: "Mandate approved",
  ACTIVE: "Active",
  PENDING: "Charge pending",
  HALTED: "Halted — charge failed",
  PAID: "Paid",
  CANCELLED: "Cancelled",
  COMPLETED: "Completed",
  EXPIRED: "Link expired",
};

const LIVE: BillingStatus[] = ["CREATED", "AUTHENTICATED", "ACTIVE", "PENDING", "HALTED"];

/**
 * The Razorpay payment link (one-time program) or AutoPay subscription (monthly program) behind an
 * enrollment: its status, the shareable link, and the controls to start or stop it. Money itself is
 * recorded by the webhook as ordinary payments, so the Payments list below this card stays the
 * single source of truth for what has been collected.
 */
export function EnrollmentBillingCard({
  enrollmentId,
  outstandingMinor,
  canManage,
  onChanged,
}: {
  enrollmentId: string;
  outstandingMinor: number;
  canManage: boolean;
  /** Called after a link is created or cancelled so the parent can refresh. */
  onChanged: () => void;
}) {
  const [billing, setBilling] = useState<EnrollmentBilling | null | undefined>(undefined);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    try {
      setBilling(await getCoachingService().getEnrollmentBilling(enrollmentId));
    } catch {
      setBilling(null);
    }
  }, [enrollmentId]);

  useEffect(() => {
    void load();
  }, [load, outstandingMinor]);

  // While a link / mandate is live, keep checking with Razorpay so the page flips to Paid the moment the
  // student finishes — on a short timer, and instantly when this tab regains focus (they usually pay in
  // another tab). The webhook records the same payment idempotently, so whichever lands first wins.
  const live = billing != null && LIVE.includes(billing.status);
  const checking = useRef(false);
  const lastSeen = useRef<string>("");
  const check = useCallback(async () => {
    if (checking.current) return;
    checking.current = true;
    try {
      await getCoachingService().reconcileEnrollmentBilling(enrollmentId);
    } catch {
      // Razorpay unreachable / function not deployed — the webhook (or the next poll) will catch up.
    }
    try {
      const fresh = await getCoachingService().getEnrollmentBilling(enrollmentId);
      const key = fresh ? `${fresh.status}:${fresh.chargeCount}` : "";
      if (key !== lastSeen.current) {
        const first = lastSeen.current === "";
        lastSeen.current = key;
        setBilling(fresh);
        if (!first) onChanged();
      }
    } finally {
      checking.current = false;
    }
  }, [enrollmentId, onChanged]);

  useEffect(() => {
    if (billing) lastSeen.current = `${billing.status}:${billing.chargeCount}`;
  }, [billing]);

  useEffect(() => {
    if (!live) return;
    void check();
    const timer = setInterval(() => void check(), 6000);
    const onFocus = () => void check();
    const onVisible = () => {
      if (document.visibilityState === "visible") void check();
    };
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearInterval(timer);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [live, check]);

  async function run(action: () => Promise<unknown>, failure: string) {
    setBusy(true);
    setError(null);
    try {
      await action();
      await load();
      onChanged();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : failure);
    } finally {
      setBusy(false);
    }
  }

  async function copy(url: string) {
    try {
      await navigator.clipboard.writeText(url);
    } catch {
      window.prompt("Copy this link:", url);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  if (billing === undefined) return null;
  // Nothing to show: no online billing and nothing left to collect (or no right to start one).
  if (!billing && (!canManage || outstandingMinor <= 0)) return null;

  const isSubscription = billing?.kind === "SUBSCRIPTION";

  return (
    <Card className="space-y-3 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="flex items-center gap-2 text-sm font-semibold">
          <Link2 className="h-4 w-4" aria-hidden />
          Online Payment
        </h3>
        {billing && <Badge variant={billing.status === "PAID" || billing.status === "ACTIVE" ? "success" : "outline"}>{STATUS_LABEL[billing.status]}</Badge>}
      </div>

      {billing ? (
        <>
          <p className="text-sm text-muted-foreground">
            {isSubscription
              ? `Monthly auto-pay · ${money(billing.amountMinor)} per month · ${billing.chargeCount} of ${billing.totalCycles} charged`
              : `Payment link · ${money(billing.amountMinor)}`}
            {isSubscription && billing.currentEnd ? ` · next cycle ends ${fmtDate(billing.currentEnd)}` : ""}
          </p>
          {live && billing.shortUrl && (
            <div className="flex items-center gap-2">
              <Input readOnly value={billing.shortUrl} className="flex-1 bg-card text-xs" />
              <Button type="button" size="sm" variant="outline" onClick={() => void copy(billing.shortUrl!)}>
                {copied ? <Check className="mr-1.5 h-3.5 w-3.5" aria-hidden /> : <Copy className="mr-1.5 h-3.5 w-3.5" aria-hidden />}
                {copied ? "Copied" : "Copy"}
              </Button>
            </div>
          )}
          {billing.status === "HALTED" && (
            <p className="text-xs text-destructive">Razorpay stopped retrying a failed charge. Ask the student to update their payment method from the link.</p>
          )}
          {canManage && live && (
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={busy}
              onClick={() => {
                const what = isSubscription ? "monthly auto-pay" : "this payment link";
                if (window.confirm(`Cancel ${what}? The student will no longer be able to pay through it.`)) {
                  void run(() => getCoachingService().cancelEnrollmentBilling(enrollmentId), "Could not cancel the online payment.");
                }
              }}
            >
              {isSubscription ? "Cancel auto-pay" : "Cancel link"}
            </Button>
          )}
          {canManage && !live && billing.status !== "PAID" && billing.status !== "COMPLETED" && outstandingMinor > 0 && (
            <Button
              type="button"
              size="sm"
              disabled={busy}
              onClick={() => void run(() => getCoachingService().createEnrollmentBilling(enrollmentId), "Could not generate a new link.")}
            >
              Generate a new link
            </Button>
          )}
        </>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            Collect {money(outstandingMinor)} online. Sends a Razorpay payment link — or, for a monthly program, sets up monthly auto-pay.
          </p>
          <Button
            type="button"
            size="sm"
            disabled={busy}
            onClick={() => void run(() => getCoachingService().createEnrollmentBilling(enrollmentId), "Could not set up the online payment.")}
          >
            {busy ? "Generating…" : "Collect online"}
          </Button>
        </>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </Card>
  );
}
