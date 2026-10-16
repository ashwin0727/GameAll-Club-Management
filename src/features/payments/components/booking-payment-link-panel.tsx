"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Check, Copy, Link2, MessageCircle } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ServiceError } from "@/services/shared/service-error";
import { getPaymentService } from "@/services/payments";
import type { BookingPaymentLink } from "@/features/payments/types";
import { paymentLinkMessage, whatsappShareUrl } from "@/features/payments/payment-link-share";
import { formatCurrency } from "@/features/pricing/money";

const POLL_MS = 10_000;

/**
 * "Pay Online" for a guest booking: instead of opening a checkout on the staff member's screen (the player
 * is not there), it makes a one-time payment link for the booking and shows it to share — copy, WhatsApp —
 * and then watches for the payment. The booking only turns Paid when Razorpay confirms the money (webhook,
 * or this panel's own status check); nothing here marks it paid by itself.
 */
export function BookingPaymentLinkPanel({
  facilityId,
  bookingId,
  guestName,
  guestPhone,
  description,
  onPaid,
}: {
  facilityId: string;
  bookingId: string;
  guestName: string;
  guestPhone: string | null;
  /** What the booking is, for the share message — e.g. "Badminton · Court 1 · 20 Oct, 6:00 PM – 8:00 PM". */
  description: string;
  /** Fires once, when the payment is confirmed. */
  onPaid?: (link: BookingPaymentLink) => void;
}) {
  const [link, setLink] = useState<BookingPaymentLink | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [checking, setChecking] = useState(false);
  const [copied, setCopied] = useState(false);
  const paidReported = useRef(false);
  const started = useRef(false);

  const apply = useCallback(
    (next: BookingPaymentLink) => {
      setLink(next);
      if (next.paid && !paidReported.current) {
        paidReported.current = true;
        onPaid?.(next);
      }
    },
    [onPaid],
  );

  const create = useCallback(async () => {
    setBusy(true);
    setError(null);
    try {
      apply(await getPaymentService().createBookingPaymentLink({ facilityId, bookingId }));
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not create the payment link.");
    } finally {
      setBusy(false);
    }
  }, [apply, facilityId, bookingId]);

  const check = useCallback(
    async (manual: boolean) => {
      if (manual) setChecking(true);
      try {
        apply(await getPaymentService().checkBookingPaymentLink({ facilityId, bookingId }));
      } catch (e) {
        if (manual) setError(e instanceof ServiceError ? e.message : "Could not check the payment.");
      } finally {
        if (manual) setChecking(false);
      }
    },
    [apply, facilityId, bookingId],
  );

  // Make (or fetch) the link once when the panel opens.
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    void create();
  }, [create]);

  // While the link is open, keep checking — on a timer, and the moment this tab is visible again.
  const open = link != null && !link.paid && link.status === "CREATED";
  useEffect(() => {
    if (!open) return;
    const tick = () => {
      if (document.visibilityState === "visible") void check(false);
    };
    const timer = setInterval(tick, POLL_MS);
    document.addEventListener("visibilitychange", tick);
    return () => {
      clearInterval(timer);
      document.removeEventListener("visibilitychange", tick);
    };
  }, [open, check]);

  async function copy(url: string) {
    try {
      await navigator.clipboard.writeText(url);
    } catch {
      window.prompt("Copy this link:", url);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  async function cancelLink() {
    setBusy(true);
    setError(null);
    try {
      apply(await getPaymentService().cancelBookingPaymentLink({ facilityId, bookingId }));
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not cancel the link.");
    } finally {
      setBusy(false);
    }
  }

  if (!link && busy) {
    return (
      <div className="rounded-lg border border-border bg-secondary/40 p-4 text-sm">
        <p className="font-medium">Creating the payment link…</p>
      </div>
    );
  }

  if (!link) {
    return (
      <div className="space-y-2 rounded-lg border border-destructive/30 bg-destructive/5 p-4 text-sm">
        <p className="font-medium text-destructive">{error ?? "Could not create the payment link."}</p>
        <p className="text-muted-foreground">The booking is saved. You can try again, or collect payment at the venue.</p>
        <Button type="button" size="sm" variant="outline" disabled={busy} onClick={() => void create()}>
          Try again
        </Button>
      </div>
    );
  }

  if (link.paid) {
    return (
      <div className="flex items-start gap-3 rounded-lg border border-success/30 bg-success/10 p-4 text-sm">
        <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-success/20 text-success">
          <Check className="h-4 w-4" />
        </span>
        <div>
          <p className="font-medium">Payment received</p>
          <p className="text-muted-foreground">The booking is confirmed and marked Paid. Nothing to collect at the venue.</p>
        </div>
      </div>
    );
  }

  const amountLabel = link.amountMinor != null ? formatCurrency(link.amountMinor, link.currency ?? "INR") : "the amount";
  const message = link.shortUrl ? paymentLinkMessage({ guestName, description, amountLabel, url: link.shortUrl }) : "";
  const closed = link.status === "CANCELLED" || link.status === "EXPIRED";

  return (
    <div className="space-y-3 rounded-lg border border-border p-4 text-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="flex items-center gap-2 font-semibold">
          <Link2 className="h-4 w-4" aria-hidden /> Payment link
        </p>
        <Badge variant={closed ? "outline" : "warning"}>{closed ? (link.status === "EXPIRED" ? "Link expired" : "Link cancelled") : "Waiting for payment"}</Badge>
      </div>

      {closed ? (
        <>
          <p className="text-muted-foreground">This link can no longer be paid. Generate a new one to collect {amountLabel}.</p>
          <Button type="button" size="sm" disabled={busy} onClick={() => void create()}>
            Generate a new link
          </Button>
        </>
      ) : (
        <>
          <p className="text-muted-foreground">
            Share this link with {guestName.trim() || "the player"}. They pay {amountLabel} on their own phone — the booking is confirmed automatically once
            the payment goes through.
          </p>
          {link.shortUrl && (
            <div className="flex items-center gap-2">
              <Input readOnly value={link.shortUrl} className="flex-1 bg-card text-xs" onFocus={(e) => e.currentTarget.select()} />
              <Button type="button" size="sm" variant="outline" onClick={() => void copy(link.shortUrl!)}>
                {copied ? <Check className="mr-1.5 h-3.5 w-3.5" aria-hidden /> : <Copy className="mr-1.5 h-3.5 w-3.5" aria-hidden />}
                {copied ? "Copied" : "Copy"}
              </Button>
            </div>
          )}
          <div className="flex flex-wrap gap-2">
            {link.shortUrl && (
              <Button asChild type="button" size="sm" variant="outline">
                <a href={whatsappShareUrl(guestPhone, message)} target="_blank" rel="noopener noreferrer">
                  <MessageCircle className="mr-1.5 h-3.5 w-3.5" aria-hidden /> Share on WhatsApp
                </a>
              </Button>
            )}
            <Button type="button" size="sm" variant="outline" disabled={checking} onClick={() => void check(true)}>
              {checking ? "Checking…" : "Check payment status"}
            </Button>
            <Button type="button" size="sm" variant="ghost" disabled={busy} onClick={() => void cancelLink()}>
              Cancel link
            </Button>
          </div>
          {link.expiresAt && <p className="text-xs text-muted-foreground">Valid until {new Date(link.expiresAt).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" })}.</p>}
        </>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
