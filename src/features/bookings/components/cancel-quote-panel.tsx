"use client";

import { useEffect, useRef, useState } from "react";
import { Input } from "@/components/ui/input";
import { formatCurrency } from "@/features/pricing/money";
import type { BookingCancellationQuote } from "@/features/refunds/types";
import { getRefundService } from "@/services/refunds";

/** What the cancel dialog needs from the panel to go ahead: the owner's own refund % (null = follow the schedule) and why. */
export interface CancelDecision {
  overridePercent: number | null;
  overrideReason: string;
  /** False while the owner is changing the refund but has not given a valid percentage and a reason yet. */
  ready: boolean;
}

/** The fixed refund schedule for a fully paid booking: [time left, % deducted]. */
export const CANCELLATION_SCHEDULE: readonly (readonly [string, number])[] = [
  ["12 hours or more", 5],
  ["11 – 12 hours", 10],
  ["10 – 11 hours", 15],
  ["9 – 10 hours", 20],
  ["8 – 9 hours", 30],
  ["7 – 8 hours", 40],
  ["6 – 7 hours", 45],
  ["5 – 6 hours", 50],
  ["4 – 5 hours", 70],
  ["3 – 4 hours", 75],
  ["2 – 3 hours", 80],
  ["1 – 2 hours", 90],
  ["Under 1 hour", 100],
];

/**
 * The refund statement of a cancellation, shown before the club confirms: the hours left, the % deducted, what is refunded and how
 * (online through Razorpay, cash handed back at the club). A booking that is only part-paid (the 50% advance) gets no refund by default;
 * the club can change the refund % for this one cancellation, with a reason. The amounts come from the database, never from here.
 */
export function CancelQuotePanel({
  bookingId,
  currency = "INR",
  onChange,
}: {
  bookingId: string;
  currency?: string;
  onChange: (decision: CancelDecision) => void;
}) {
  const [quote, setQuote] = useState<BookingCancellationQuote | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "failed">("loading");
  const [override, setOverride] = useState(false);
  const [percent, setPercent] = useState("100");
  const [reason, setReason] = useState("");
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  const pct = Number(percent);
  const pctValid = percent.trim() !== "" && Number.isFinite(pct) && pct >= 0 && pct <= 100;
  const overridePercent = override && pctValid ? Math.round(pct) : null;

  // the quote for the schedule, or for the club's own %, whichever is chosen
  useEffect(() => {
    let active = true;
    setState((s) => (s === "ready" ? s : "loading"));
    const timer = setTimeout(
      () => {
        void getRefundService()
          .bookingCancellationQuote(bookingId, overridePercent ?? undefined)
          .then((q) => {
            if (!active) return;
            setQuote(q);
            setState(q ? "ready" : "failed");
          });
      },
      overridePercent == null ? 0 : 350,
    );
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [bookingId, overridePercent]);

  useEffect(() => {
    onChangeRef.current({
      overridePercent,
      overrideReason: reason.trim(),
      ready: state === "ready" && (!override || (pctValid && reason.trim().length >= 3)),
    });
  }, [overridePercent, override, pctValid, reason, state]);

  const money = (minor: number) => formatCurrency(minor, currency);

  if (state === "failed") {
    return <p className="text-sm text-destructive">We couldn&apos;t work out the refund just now. Close this and try again.</p>;
  }
  if (!quote) return <p className="text-sm text-muted-foreground">Working out the refund…</p>;

  const refundTone = quote.refundMinor > 0 ? "border-primary/30 bg-primary/10" : quote.paidMinor === 0 ? "border-border bg-muted/40" : "border-destructive/40 bg-destructive/10";

  return (
    <div className="space-y-3 text-sm">
      <p data-testid="cancel-message" className={`rounded-lg border p-3 ${refundTone}`}>
        {quote.message}
      </p>

      {quote.paidMinor > 0 && (
        <dl className="space-y-1" data-testid="cancel-breakdown">
          <div className="flex justify-between">
            <dt className="text-muted-foreground">Amount paid</dt>
            <dd>{money(quote.paidMinor)}</dd>
          </div>
          <div className="flex justify-between">
            <dt className="text-muted-foreground">Deduction ({quote.deductionPercent}%)</dt>
            <dd className={quote.deductionMinor > 0 ? "text-destructive" : undefined}>{quote.deductionMinor > 0 ? `− ${money(quote.deductionMinor)}` : money(0)}</dd>
          </div>
          <div className="flex justify-between border-t border-border pt-1 font-semibold">
            <dt>Refund to the customer</dt>
            <dd>{money(quote.refundMinor)}</dd>
          </div>
          {quote.onlineRefundMinor > 0 && (
            <div className="flex justify-between text-xs text-muted-foreground">
              <dt>Refunded online through Razorpay</dt>
              <dd>{money(quote.onlineRefundMinor)}</dd>
            </div>
          )}
          {quote.offlineRefundDueMinor > 0 && (
            <div className="flex justify-between text-xs text-amber-600">
              <dt>Cash to hand back at the club</dt>
              <dd>{money(quote.offlineRefundDueMinor)}</dd>
            </div>
          )}
        </dl>
      )}

      {quote.paidMinor > 0 && (
        <div className="rounded-lg border border-border p-3">
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={override} onChange={(e) => setOverride(e.target.checked)} />
            Change the refund for this cancellation (club decision)
          </label>
          {override && (
            <div className="mt-3 grid gap-3 sm:grid-cols-[8rem_1fr]">
              <label className="space-y-1 text-xs text-muted-foreground">
                Refund (% of what was paid)
                <Input value={percent} onChange={(e) => setPercent(e.target.value)} inputMode="numeric" aria-label="Refund percent" />
              </label>
              <label className="space-y-1 text-xs text-muted-foreground">
                Reason (required)
                <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Court was unavailable" aria-label="Override reason" />
              </label>
              {!pctValid && <p className="text-xs text-destructive sm:col-span-2">Enter a refund between 0 and 100.</p>}
            </div>
          )}
        </div>
      )}

      <details className="rounded-lg border border-border p-3 text-xs">
        <summary className="cursor-pointer font-medium text-primary">See the refund rules</summary>
        <ul className="mt-2 space-y-1">
          {CANCELLATION_SCHEDULE.map(([label, p]) => (
            <li key={label} className="flex justify-between gap-3">
              <span className="text-muted-foreground">Cancelled with {label} left</span>
              <span>{p}% deducted</span>
            </li>
          ))}
        </ul>
        <p className="mt-2 text-muted-foreground">Applies when the booking is paid in full. If only the 50% advance is paid there is no refund, unless the club changes it.</p>
      </details>
    </div>
  );
}

/** The sentence shown after the booking was cancelled. */
export function cancelledNote(
  c: { refundMinor: number; paidMinor: number; offlineRefundDueMinor: number; onlineRefundMinor: number } | null,
  currency = "INR",
): string {
  if (!c || c.paidMinor <= 0) return "Booking cancelled.";
  if (c.refundMinor <= 0) return "Booking cancelled. No refund applies.";
  const online = c.onlineRefundMinor > 0 ? ` ${formatCurrency(c.onlineRefundMinor, currency)} is being refunded through Razorpay (5–7 working days).` : "";
  const cash = c.offlineRefundDueMinor > 0 ? ` ${formatCurrency(c.offlineRefundDueMinor, currency)} was paid in cash: please hand it back at the club.` : "";
  return `Booking cancelled.${online}${cash}`;
}
