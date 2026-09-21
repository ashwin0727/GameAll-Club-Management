"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { SelectField } from "@/features/bookings/components/select-field";
import { formatClock } from "@/features/bookings/components/booking-event-style";
import { formatCurrency, fromMinorUnits, toMinorUnits } from "@/features/pricing/money";
import type { Booking } from "@/features/bookings/types";
import { TYPE_LABEL, type BookingRow } from "@/features/bookings/list-utils";
import { getBookingService } from "@/services/bookings";
import { getRefundService } from "@/services/refunds";
import { ServiceError } from "@/services/shared/service-error";
import { cn } from "@/lib/utils";

const FIELD =
  "h-10 w-full rounded-[8px] border border-input bg-card px-3 text-sm outline-none focus-visible:border-foreground/40";

function errorText(e: unknown, fallback: string): string {
  return e instanceof ServiceError ? e.message : fallback;
}

function DialogShell({
  title,
  description,
  onClose,
  children,
  footer,
}: {
  title: string;
  description?: string;
  onClose: () => void;
  children: React.ReactNode;
  footer: React.ReactNode;
}) {
  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        {children}
        <DialogFooter>{footer}</DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="text-sm font-medium">{value}</p>
    </div>
  );
}

const DATE_FMT = new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short", year: "numeric" });

/* ── Cancel ───────────────────────────────────────────────────────────────── */

/**
 * Cancel with a reason. Goes through the same server-side cancel the details
 * dialog uses, so a paid booking also gets its policy-derived refund requested.
 */
export function CancelBookingDialog({
  booking,
  onClose,
  onDone,
}: {
  booking: Booking;
  onClose: () => void;
  onDone: () => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const paid = booking.paymentStatus === "PAID";

  async function confirm() {
    setBusy(true);
    setError(null);
    try {
      const { refund } = await getRefundService().cancelBooking({
        bookingId: booking.id,
        reason: reason.trim() || "Owner Request",
      });
      onDone();
      if (refund) {
        setNote(
          refund.status === "FAILED"
            ? "The booking was cancelled, but the refund could not be submitted. Please retry from Refunds."
            : "Booking cancelled. A refund was requested and will show as processed once it is confirmed.",
        );
        setBusy(false);
      } else {
        onClose();
      }
    } catch (e) {
      setError(errorText(e, "Unable to cancel this booking."));
      setBusy(false);
    }
  }

  return (
    <DialogShell
      title="Cancel booking"
      description={
        paid
          ? "This booking is paid. Cancelling it requests a refund according to your cancellation policy."
          : "The court is released for other bookings. This can't be undone."
      }
      onClose={onClose}
      footer={
        note ? (
          <Button type="button" onClick={onClose}>
            Done
          </Button>
        ) : (
          <>
            <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
              Keep booking
            </Button>
            <Button type="button" variant="destructive" onClick={confirm} disabled={busy}>
              {busy ? "Cancelling…" : "Cancel booking"}
            </Button>
          </>
        )
      }
    >
      {note ? (
        <p className="text-sm text-muted-foreground">{note}</p>
      ) : (
        <div className="space-y-2">
          <label className="text-xs text-muted-foreground" htmlFor="cancel-reason">
            Reason (optional)
          </label>
          <textarea
            id="cancel-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
            maxLength={300}
            placeholder="e.g. Customer asked to cancel"
            className="w-full rounded-[8px] border border-input bg-card px-3 py-2 text-sm outline-none focus-visible:border-foreground/40"
          />
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
      )}
    </DialogShell>
  );
}

/* ── Change court ─────────────────────────────────────────────────────────── */

/** Move to another court at the same date and time; only courts that are free then can be picked. */
export function ChangeCourtDialog({
  booking,
  courts,
  onClose,
  onDone,
}: {
  booking: Booking;
  courts: { id: string; name: string }[];
  onClose: () => void;
  onDone: () => void;
}) {
  const others = courts.filter((c) => c.id !== booking.courtId);
  const [free, setFree] = useState<Record<string, boolean> | null>(null);
  const [picked, setPicked] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const start = new Date(booking.startTime);
    const end = new Date(booking.endTime);
    Promise.all(
      others.map(async (c) => {
        const day = await getBookingService().getBookingsForCourtOnDate(c.id, start);
        const clash = day.some(
          (b) => (b.status === "pending" || b.status === "confirmed") && new Date(b.startTime) < end && start < new Date(b.endTime),
        );
        return [c.id, !clash] as const;
      }),
    )
      .then((entries) => !cancelled && setFree(Object.fromEntries(entries)))
      .catch(() => !cancelled && setFree({}));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [booking.id]);

  async function confirm() {
    setBusy(true);
    setError(null);
    try {
      await getBookingService().rescheduleBooking({
        bookingId: booking.id,
        courtId: picked,
        startTime: booking.startTime,
        endTime: booking.endTime,
      });
      onDone();
      onClose();
    } catch (e) {
      setError(errorText(e, "Unable to move this booking."));
      setBusy(false);
    }
  }

  const when = `${DATE_FMT.format(new Date(booking.startTime))} · ${formatClock(new Date(booking.startTime))} – ${formatClock(new Date(booking.endTime))}`;

  return (
    <DialogShell
      title="Change court"
      description={`Same time, different court: ${when}`}
      onClose={onClose}
      footer={
        <>
          <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
            Back
          </Button>
          <Button type="button" onClick={confirm} disabled={!picked || busy}>
            {busy ? "Moving…" : "Move booking"}
          </Button>
        </>
      }
    >
      <div className="space-y-2">
        {others.length === 0 ? (
          <p className="text-sm text-muted-foreground">There are no other courts for this sport.</p>
        ) : free === null ? (
          <p className="text-sm text-muted-foreground">Checking availability…</p>
        ) : (
          others.map((c) => {
            const isFree = free[c.id] !== false;
            return (
              <label
                key={c.id}
                className={cn(
                  "flex cursor-pointer items-center justify-between rounded-[8px] border px-3 py-2.5 text-sm",
                  picked === c.id ? "border-primary bg-primary/5" : "border-input",
                  !isFree && "cursor-not-allowed opacity-50",
                )}
              >
                <span className="flex items-center gap-2">
                  <input
                    type="radio"
                    name="court"
                    disabled={!isFree}
                    checked={picked === c.id}
                    onChange={() => setPicked(c.id)}
                    className="accent-[#0B7A55]"
                  />
                  {c.name}
                </span>
                <span className={cn("text-xs font-medium", isFree ? "text-success" : "text-destructive")}>
                  {isFree ? "Available" : "Booked at this time"}
                </span>
              </label>
            );
          })
        )}
        {error && <p className="text-sm text-destructive">{error}</p>}
      </div>
    </DialogShell>
  );
}

/* ── Mark payment (guest bookings) ────────────────────────────────────────── */

const METHODS = ["Cash", "UPI", "Card", "Bank Transfer", "Other"];

/** Record money taken offline; the booking flips to paid (and confirmed). */
export function MarkPaymentDialog({
  booking,
  onClose,
  onDone,
}: {
  booking: Booking;
  onClose: () => void;
  onDone: () => void;
}) {
  const [method, setMethod] = useState("Cash");
  const [amount, setAmount] = useState(
    booking.amountMinor != null ? String(fromMinorUnits(booking.amountMinor, booking.currency)) : "",
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function confirm() {
    const value = Number(amount);
    if (!Number.isFinite(value) || value <= 0) {
      setError("Enter the amount received.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getBookingService().recordGuestBookingPayment(booking.id, method, toMinorUnits(value, booking.currency));
      onDone();
      onClose();
    } catch (e) {
      setError(errorText(e, "Unable to record this payment."));
      setBusy(false);
    }
  }

  return (
    <DialogShell
      title="Mark payment"
      description={
        booking.amountMinor != null
          ? `Booking total ${formatCurrency(booking.amountMinor, booking.currency)}. Record what you collected.`
          : "Record what you collected."
      }
      onClose={onClose}
      footer={
        <>
          <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
            Back
          </Button>
          <Button type="button" onClick={confirm} disabled={busy}>
            {busy ? "Saving…" : "Record payment"}
          </Button>
        </>
      }
    >
      <div className="space-y-3">
        <label className="block space-y-1 text-xs text-muted-foreground">
          Method
          <SelectField
            value={method}
            onValueChange={setMethod}
            options={METHODS.map((m) => ({ value: m, label: m }))}
            className={cn(FIELD, "text-foreground")}
          />
        </label>
        <label className="block space-y-1 text-xs text-muted-foreground">
          Amount received
          <input
            type="number"
            inputMode="decimal"
            min="0"
            step="0.01"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className={cn(FIELD, "text-foreground")}
          />
        </label>
        {error && <p className="text-sm text-destructive">{error}</p>}
      </div>
    </DialogShell>
  );
}

/* ── Duplicate (guest bookings) ───────────────────────────────────────────── */

function localInputValue(d: Date): string {
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60000).toISOString().slice(0, 16);
}

/** Copy a guest booking to a new start time; the server checks that the court is free. */
export function DuplicateBookingDialog({
  booking,
  onClose,
  onDone,
}: {
  booking: Booking;
  onClose: () => void;
  onDone: () => void;
}) {
  const length = new Date(booking.endTime).getTime() - new Date(booking.startTime).getTime();
  const [start, setStart] = useState(localInputValue(new Date(new Date(booking.startTime).getTime() + 7 * 86_400_000)));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function confirm() {
    const s = new Date(start);
    if (Number.isNaN(s.getTime())) {
      setError("Pick a start time.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getBookingService().duplicateGuestBooking(booking.id, s.toISOString(), new Date(s.getTime() + length).toISOString());
      onDone();
      onClose();
    } catch (e) {
      setError(errorText(e, "Unable to duplicate this booking."));
      setBusy(false);
    }
  }

  return (
    <DialogShell
      title="Duplicate booking"
      description="Creates a new pending booking for the same guest and court, with the same length."
      onClose={onClose}
      footer={
        <>
          <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
            Back
          </Button>
          <Button type="button" onClick={confirm} disabled={busy}>
            {busy ? "Creating…" : "Create copy"}
          </Button>
        </>
      }
    >
      <div className="space-y-2">
        <label className="block space-y-1 text-xs text-muted-foreground">
          New start
          <input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} className={cn(FIELD, "text-foreground")} />
        </label>
        {error && <p className="text-sm text-destructive">{error}</p>}
      </div>
    </DialogShell>
  );
}

/* ── Read-only views ──────────────────────────────────────────────────────── */

/** Payment / refund summary from the booking itself, with a way into Finance or Refunds. */
export function PaymentDetailsDialog({
  booking,
  refundView,
  canOpenFinance,
  onClose,
}: {
  booking: Booking;
  /** Cancelled bookings: point at Refunds instead of Transactions. */
  refundView: boolean;
  canOpenFinance: boolean;
  onClose: () => void;
}) {
  const paid = booking.paymentStatus === "PAID";
  return (
    <DialogShell
      title={refundView ? "Payment & refund" : "Payment details"}
      onClose={onClose}
      footer={
        <>
          {canOpenFinance && (
            <Button asChild variant="outline">
              <Link href={refundView ? "/refunds" : "/finance/transactions"}>{refundView ? "Open Refunds" : "Open in Finance"}</Link>
            </Button>
          )}
          <Button type="button" onClick={onClose}>
            Close
          </Button>
        </>
      }
    >
      <div className="grid grid-cols-2 gap-3">
        <Row label="Payment status" value={<span className="capitalize">{booking.paymentStatus.toLowerCase()}</span>} />
        <Row label="Amount" value={booking.amountMinor != null ? formatCurrency(booking.amountMinor, booking.currency) : "—"} />
        <Row label="Method" value={booking.paymentMethod ?? "—"} />
        <Row label="Booking status" value={<span className="capitalize">{booking.status}</span>} />
      </div>
      {refundView && paid && (
        <p className="text-sm text-muted-foreground">
          This booking was paid before it was cancelled. Any refund it triggered is listed under Refunds.
        </p>
      )}
      {refundView && !paid && <p className="text-sm text-muted-foreground">No payment was collected, so there is nothing to refund.</p>}
    </DialogShell>
  );
}

export function CancellationReasonDialog({ booking, onClose }: { booking: Booking; onClose: () => void }) {
  return (
    <DialogShell
      title="Cancellation reason"
      onClose={onClose}
      footer={
        <Button type="button" onClick={onClose}>
          Close
        </Button>
      }
    >
      <div className="space-y-3">
        <p className="text-sm">{booking.cancellationReason?.trim() || "No reason was recorded."}</p>
        <Row label="Cancelled" value={DATE_FMT.format(new Date(booking.updatedAt))} />
      </div>
    </DialogShell>
  );
}

/** Full contact details — only reachable with the "view customer details" permission. */
export function CustomerDialog({ row, onClose }: { row: BookingRow; onClose: () => void }) {
  // The label is Guest for every court booking; where to look the person up depends on who they really are.
  const isMember = row.booking?.customerType === "MEMBER";
  return (
    <DialogShell
      title="Customer"
      onClose={onClose}
      footer={
        <>
          <Button asChild variant="outline">
            <Link href={isMember ? "/memberships" : "/guests"}>{isMember ? "Open Members" : "Open Guest Players"}</Link>
          </Button>
          <Button type="button" onClick={onClose}>
            Close
          </Button>
        </>
      }
    >
      <div className="grid grid-cols-2 gap-3">
        <Row label="Name" value={row.customerName} />
        <Row label="Type" value={TYPE_LABEL[row.kind]} />
        <Row label="Phone" value={row.customerPhone ?? "—"} />
        <Row label="Reference" value={row.reference} />
      </div>
    </DialogShell>
  );
}
