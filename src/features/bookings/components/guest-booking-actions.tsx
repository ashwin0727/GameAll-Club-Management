"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Eye, MoreVertical, CheckCircle2, XCircle, Mail, Copy, FileDown, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { getBookingService } from "@/services/bookings";
import { getRefundService } from "@/services/refunds";
import { ServiceError } from "@/services/shared/service-error";
import { usePaymentCheckout } from "@/features/payments/use-payment-checkout";
import { PaymentStatusPanel, type PaymentStatusPanelState } from "@/features/payments/components/payment-status-panel";
import { formatCurrency } from "@/features/pricing/money";
import { buildBookingDocument, openPrintable } from "@/features/bookings/booking-document";
import type { GuestBookingRow } from "@/features/bookings/types";

const METHODS = ["Cash", "UPI", "Card", "Bank Transfer", "Other"];

type Action = "complete" | "cancel" | "receipt" | "duplicate" | "delete" | "record-payment" | null;

function money(minor: number | null, currency: string) {
  return minor == null ? "—" : formatCurrency(minor, currency);
}
function localDatetimeValue(iso: string): string {
  const d = new Date(iso);
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60000).toISOString().slice(0, 16);
}

export function GuestBookingActions({
  row,
  facilityId,
  facilityName,
  onChanged,
}: {
  row: GuestBookingRow;
  facilityId: string;
  facilityName: string;
  onChanged: () => void;
}) {
  const router = useRouter();
  const [action, setAction] = useState<Action>(null);
  const isSession = row.source === "SESSION";
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const openEdit = () => router.push(`/guest-bookings/${row.bookingId}/edit`);
  const close = () => {
    setAction(null);
    setError(null);
    setBusy(false);
  };

  return (
    <div className="flex items-center justify-end gap-1">
      <Button
        type="button"
        variant="ghost"
        size="icon"
        aria-label={isSession ? "Session seats are managed under Membership Sessions" : "Edit booking"}
        title={isSession ? "Managed under Membership Sessions" : undefined}
        disabled={isSession}
        onClick={openEdit}
      >
        <Eye className="h-4 w-4" />
      </Button>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button type="button" variant="ghost" size="icon" aria-label="More actions">
            <MoreVertical className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          {isSession ? (
            // A released membership seat has no court booking behind it, so
            // the actions that operate on one don't apply. Taking the money
            // and printing a bill still do.
            <>
              <ActionItem
                icon={CheckCircle2}
                title="Record Payment"
                sub="Mark payment as received"
                onClick={() => setAction("record-payment")}
                disabled={row.paymentStatus === "PAID" || row.status === "cancelled"}
              />
              <ActionItem icon={FileDown} title="Download Invoice" sub="Download invoice / bill" onClick={() => openPrintable(buildBookingDocument("invoice", row, facilityName))} />
            </>
          ) : (
            <>
              <ActionItem icon={CheckCircle2} title="Mark as Completed" sub="Mark booking as completed" onClick={() => setAction("complete")} disabled={row.status === "cancelled" || row.status === "completed"} />
              <ActionItem icon={XCircle} title="Cancel Booking" sub="Cancel this booking" onClick={() => setAction("cancel")} disabled={row.status === "cancelled"} danger />
              <DropdownMenuSeparator />
              <ActionItem icon={Mail} title="Send Receipt" sub="Send booking receipt to guest" onClick={() => setAction("receipt")} />
              <ActionItem icon={Copy} title="Duplicate Booking" sub="Create a new booking" onClick={() => setAction("duplicate")} />
              <ActionItem icon={FileDown} title="Download Invoice" sub="Download invoice / bill" onClick={() => openPrintable(buildBookingDocument("invoice", row, facilityName))} />
              <DropdownMenuSeparator />
              <ActionItem icon={Trash2} title="Delete Booking" sub="Permanently delete booking" onClick={() => setAction("delete")} danger />
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {action === "complete" && (
        <CompleteDialog row={row} facilityId={facilityId} busy={busy} error={error} setBusy={setBusy} setError={setError} onClose={close} onDone={() => { close(); onChanged(); }} />
      )}
      {action === "cancel" && (
        <CancelDialog row={row} busy={busy} error={error} setBusy={setBusy} setError={setError} onClose={close} onDone={() => { close(); onChanged(); }} />
      )}
      {action === "receipt" && (
        <ReceiptDialog row={row} busy={busy} error={error} setBusy={setBusy} setError={setError} onClose={close} />
      )}
      {action === "duplicate" && (
        <DuplicateDialog row={row} facilityId={facilityId} busy={busy} error={error} setBusy={setBusy} setError={setError} onClose={close} onDone={() => { close(); onChanged(); }} />
      )}
      {action === "record-payment" && (
        <RecordSessionPaymentDialog
          row={row}
          busy={busy}
          error={error}
          setBusy={setBusy}
          setError={setError}
          onClose={close}
          onDone={() => { close(); onChanged(); }}
        />
      )}
      {action === "delete" && (
        <ConfirmDialog
          title="Delete booking"
          description="Permanently delete this booking. This cannot be undone. Bookings with a settled payment can't be deleted — cancel & refund instead."
          confirmLabel="Delete"
          danger
          busy={busy}
          error={error}
          onCancel={close}
          onConfirm={async () => {
            setBusy(true);
            setError(null);
            try {
              await getBookingService().deleteGuestBooking(row.bookingId);
              close();
              onChanged();
            } catch (e) {
              setError(e instanceof ServiceError ? e.message : "Unable to delete this booking.");
              setBusy(false);
            }
          }}
        />
      )}
    </div>
  );
}

function ActionItem({
  icon: Icon,
  title,
  sub,
  onClick,
  disabled,
  danger,
}: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  sub: string;
  onClick: () => void;
  disabled?: boolean;
  danger?: boolean;
}) {
  return (
    <DropdownMenuItem disabled={disabled} onClick={onClick} className={danger ? "text-destructive focus:text-destructive" : undefined}>
      <Icon className="mr-2 mt-0.5 h-4 w-4 shrink-0" />
      <span className="flex flex-col">
        <span className="text-sm font-medium">{title}</span>
        <span className="text-[11px] text-muted-foreground">{sub}</span>
      </span>
    </DropdownMenuItem>
  );
}

/* ── shared confirm ─────────────────────────────────────────────────────── */
function ConfirmDialog({
  title,
  description,
  confirmLabel,
  danger,
  busy,
  error,
  onCancel,
  onConfirm,
  children,
}: {
  title: string;
  description?: string;
  confirmLabel: string;
  danger?: boolean;
  busy: boolean;
  error: string | null;
  onCancel: () => void;
  onConfirm: () => void;
  children?: React.ReactNode;
}) {
  return (
    <Dialog open onOpenChange={(o) => !o && !busy && onCancel()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        {children}
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button type="button" variant="outline" disabled={busy} onClick={onCancel}>
            Cancel
          </Button>
          <Button type="button" variant={danger ? "destructive" : "default"} disabled={busy} onClick={onConfirm}>
            {busy ? "Working…" : confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* ── Record Payment (released membership seat) ──────────────────────────── */
/**
 * Offline payment for a seat released from a membership session. Those rows
 * live in membership_session_bookings rather than bookings, so they take the
 * sibling recorder — which writes to the same payments table, and therefore
 * lands in Finance the same way a court booking's cash does.
 */
function RecordSessionPaymentDialog({
  row,
  busy,
  error,
  setBusy,
  setError,
  onClose,
  onDone,
}: {
  row: GuestBookingRow;
  busy: boolean;
  error: string | null;
  setBusy: (v: boolean) => void;
  setError: (v: string | null) => void;
  onClose: () => void;
  onDone: () => void;
}) {
  const [method, setMethod] = useState("Cash");
  const [amount, setAmount] = useState(row.amountMinor != null ? String(row.amountMinor / 100) : "");

  async function run() {
    setBusy(true);
    setError(null);
    try {
      await getBookingService().recordSessionGuestPayment(
        row.bookingId,
        method,
        Math.round((Number(amount) || 0) * 100),
      );
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to record this payment.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Record payment</DialogTitle>
          <DialogDescription>
            {row.guestName} · {money(row.amountMinor, row.currency)}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <label htmlFor="session-pay-method" className="text-sm font-medium">
              Payment method
            </label>
            <div className="flex flex-wrap gap-2">
              {METHODS.map((m) => (
                <Button
                  key={m}
                  type="button"
                  variant={m === method ? "default" : "outline"}
                  size="sm"
                  onClick={() => setMethod(m)}
                >
                  {m}
                </Button>
              ))}
            </div>
          </div>
          <div className="space-y-1.5">
            <label htmlFor="session-pay-amount" className="text-sm font-medium">
              Amount received
            </label>
            <Input
              id="session-pay-amount"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button type="button" onClick={run} disabled={busy}>
            {busy ? "Recording…" : "Record payment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* ── Mark as Completed ──────────────────────────────────────────────────── */
function CompleteDialog({
  row,
  facilityId,
  busy,
  error,
  setBusy,
  setError,
  onClose,
  onDone,
}: {
  row: GuestBookingRow;
  facilityId: string;
  busy: boolean;
  error: string | null;
  setBusy: (v: boolean) => void;
  setError: (v: string | null) => void;
  onClose: () => void;
  onDone: () => void;
}) {
  const alreadyPaid = row.paymentStatus === "PAID";
  const [mode, setMode] = useState<"offline" | "online">("offline");
  const [method, setMethod] = useState("Cash");
  const [amount, setAmount] = useState(row.amountMinor != null ? String(row.amountMinor / 100) : "");
  const [paymentState, setPaymentState] = useState<PaymentStatusPanelState | null>(null);
  const { startCheckout, isProcessing } = usePaymentCheckout();

  async function run() {
    setBusy(true);
    setError(null);
    try {
      if (!alreadyPaid) {
        if (mode === "offline") {
          await getBookingService().recordGuestBookingPayment(row.bookingId, method, Math.round((Number(amount) || 0) * 100));
        } else {
          setBusy(false);
          setPaymentState("processing");
          const result = await startCheckout(
            { facilityId, sourceType: "GUEST_BOOKING", bookingId: row.bookingId },
            { description: `${row.sportName ?? "Court"} · ${row.courtName}`, prefill: { name: row.guestName, contact: row.guestPhone ?? undefined } },
          );
          if (result.status === "cancelled") {
            setPaymentState(null);
            return;
          }
          setPaymentState(result);
          if (result.status !== "settled") return;
        }
      }
      await getBookingService().completeGuestBooking(row.bookingId);
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to complete this booking.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && !busy && !isProcessing && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Mark as Completed</DialogTitle>
          <DialogDescription>
            {alreadyPaid ? "This booking is paid — it will be marked completed." : "Collect the payment, then the booking is marked completed."}
          </DialogDescription>
        </DialogHeader>

        {paymentState ? (
          <PaymentStatusPanel state={paymentState} settledLabel="Payment received" resourceLabel="booking" />
        ) : alreadyPaid ? null : (
          <div className="space-y-3">
            <div className="space-y-2 text-sm">
              <label className={"flex items-start gap-2 rounded-lg border p-2 " + (mode === "offline" ? "border-primary" : "border-border")}>
                <input type="radio" className="mt-0.5" checked={mode === "offline"} onChange={() => setMode("offline")} />
                <span>
                  Payment collected offline
                  <span className="block text-xs text-muted-foreground">Cash / UPI / card at the venue</span>
                </span>
              </label>
              <label className={"flex items-start gap-2 rounded-lg border p-2 " + (mode === "online" ? "border-primary" : "border-border")}>
                <input type="radio" className="mt-0.5" checked={mode === "online"} onChange={() => setMode("online")} />
                <span>
                  Collect online now
                  <span className="block text-xs text-muted-foreground">Razorpay checkout — {money(row.amountMinor, row.currency)}</span>
                </span>
              </label>
            </div>
            {mode === "offline" && (
              <div className="grid grid-cols-2 gap-2">
                <label className="space-y-1 text-xs text-muted-foreground">
                  Method
                  <select value={method} onChange={(e) => setMethod(e.target.value)} className="h-9 w-full rounded-md border border-input bg-secondary/60 px-2 text-sm">
                    {METHODS.map((m) => (
                      <option key={m}>{m}</option>
                    ))}
                  </select>
                </label>
                <label className="space-y-1 text-xs text-muted-foreground">
                  Amount (₹)
                  <Input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" />
                </label>
              </div>
            )}
          </div>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button type="button" variant="outline" disabled={busy || isProcessing} onClick={onClose}>
            {paymentState ? "Close" : "Cancel"}
          </Button>
          {!paymentState && (
            <Button type="button" disabled={busy || isProcessing} onClick={run}>
              {busy || isProcessing ? "Working…" : alreadyPaid ? "Mark Completed" : mode === "online" ? "Collect & Complete" : "Record & Complete"}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* ── Cancel Booking ─────────────────────────────────────────────────────── */
function CancelDialog({
  row,
  busy,
  error,
  setBusy,
  setError,
  onClose,
  onDone,
}: {
  row: GuestBookingRow;
  busy: boolean;
  error: string | null;
  setBusy: (v: boolean) => void;
  setError: (v: string | null) => void;
  onClose: () => void;
  onDone: () => void;
}) {
  const isPaid = row.paymentStatus === "PAID";
  const [reason, setReason] = useState("");
  const [refund, setRefund] = useState(isPaid);
  const [amount, setAmount] = useState(row.amountMinor != null ? String(row.amountMinor / 100) : "");

  async function run() {
    setBusy(true);
    setError(null);
    try {
      if (isPaid) {
        const total = row.amountMinor ?? 0;
        const pct = refund && total > 0 ? Math.max(0, Math.min(100, Math.round(((Number(amount) || 0) * 100 * 100) / total))) : 0;
        await getRefundService().cancelBooking({ bookingId: row.bookingId, reason: reason.trim() || undefined, refundOverridePercent: pct });
      } else {
        await getBookingService().cancelBooking(row.bookingId, reason.trim() || undefined);
      }
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to cancel this booking.");
      setBusy(false);
    }
  }

  return (
    <ConfirmDialog
      title="Cancel booking"
      description="The court frees up immediately. This can't be undone."
      confirmLabel="Cancel Booking"
      danger
      busy={busy}
      error={error}
      onCancel={onClose}
      onConfirm={run}
    >
      <div className="space-y-3">
        <label className="block space-y-1 text-xs text-muted-foreground">
          Reason (optional)
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Guest no-show" />
        </label>
        {isPaid && (
          <>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={refund} onChange={(e) => setRefund(e.target.checked)} />
              Issue a refund for this booking
            </label>
            {refund && (
              <label className="block space-y-1 text-xs text-muted-foreground">
                Refund amount (₹) — paid {money(row.amountMinor, row.currency)}
                <Input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" />
              </label>
            )}
          </>
        )}
      </div>
    </ConfirmDialog>
  );
}

/* ── Send Receipt ──────────────────────────────────────────────────────── */
function ReceiptDialog({
  row,
  busy,
  error,
  setBusy,
  setError,
  onClose,
}: {
  row: GuestBookingRow;
  busy: boolean;
  error: string | null;
  setBusy: (v: boolean) => void;
  setError: (v: string | null) => void;
  onClose: () => void;
}) {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);

  async function run() {
    if (!/^\S+@\S+\.\S+$/.test(email.trim())) {
      setError("Enter a valid email address.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getBookingService().sendBookingReceipt(row.bookingId, email.trim());
      setSent(true);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not send the receipt.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Send Receipt</DialogTitle>
          <DialogDescription>Send booking receipt to guest — a PDF receipt is emailed to this address.</DialogDescription>
        </DialogHeader>
        {sent ? (
          <p className="text-sm text-success">Receipt sent to {email}.</p>
        ) : (
          <label className="block space-y-1 text-xs text-muted-foreground">
            Guest email
            <Input value={email} onChange={(e) => setEmail(e.target.value)} type="email" placeholder="guest@example.com" autoFocus />
          </label>
        )}
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose}>
            {sent ? "Done" : "Cancel"}
          </Button>
          {!sent && (
            <Button type="button" disabled={busy} onClick={run}>
              {busy ? "Sending…" : "Send Receipt"}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/* ── Duplicate Booking ─────────────────────────────────────────────────── */
function DuplicateDialog({
  row,
  facilityId,
  busy,
  error,
  setBusy,
  setError,
  onClose,
  onDone,
}: {
  row: GuestBookingRow;
  facilityId: string;
  busy: boolean;
  error: string | null;
  setBusy: (v: boolean) => void;
  setError: (v: string | null) => void;
  onClose: () => void;
  onDone: () => void;
}) {
  const durationMs = new Date(row.endTime).getTime() - new Date(row.startTime).getTime();
  const [start, setStart] = useState(() => {
    const d = new Date(row.startTime);
    d.setDate(d.getDate() + 7);
    return localDatetimeValue(d.toISOString());
  });
  const [newBookingId, setNewBookingId] = useState<string | null>(null);

  async function create() {
    setBusy(true);
    setError(null);
    try {
      const startIso = new Date(start).toISOString();
      const endIso = new Date(new Date(start).getTime() + durationMs).toISOString();
      const b = await getBookingService().duplicateGuestBooking(row.bookingId, startIso, endIso);
      setNewBookingId(b.id);
      setBusy(false);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to duplicate this booking.");
      setBusy(false);
    }
  }

  if (newBookingId) {
    // Chain into the payment decision for the fresh (PENDING) booking.
    return (
      <CompleteDialog
        row={{ ...row, bookingId: newBookingId, paymentStatus: "PENDING", status: "confirmed", startTime: new Date(start).toISOString(), endTime: new Date(new Date(start).getTime() + durationMs).toISOString() }}
        facilityId={facilityId}
        busy={busy}
        error={error}
        setBusy={setBusy}
        setError={setError}
        onClose={() => {
          onDone();
        }}
        onDone={onDone}
      />
    );
  }

  return (
    <ConfirmDialog
      title="Duplicate booking"
      description="Creates a new booking with the same guest, court and players. Pick when it should be."
      confirmLabel="Duplicate"
      busy={busy}
      error={error}
      onCancel={onClose}
      onConfirm={create}
    >
      <label className="block space-y-1 text-xs text-muted-foreground">
        New start
        <Input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
      </label>
    </ConfirmDialog>
  );
}
