"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { getBookingService } from "@/services/bookings";
import { getRefundService } from "@/services/refunds";
import { getOperatingHoursService } from "@/services/operating-hours";
import { computeAvailableSlots } from "@/features/bookings/slots";
import { formatCurrency } from "@/features/pricing/money";
import type { Booking, TimeSlot } from "@/features/bookings/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { ServiceError } from "@/services/shared/service-error";
import { usePaymentCheckout, type CheckoutResult } from "@/features/payments/use-payment-checkout";
import { PaymentStatusPanel, type PaymentStatusPanelState } from "@/features/payments/components/payment-status-panel";

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true });
}

export function BookingDetailsDialog({
  open,
  onOpenChange,
  booking,
  court,
  sportName,
  facilityId,
  onChanged,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  booking: Booking | null;
  court: PlayingArea | undefined;
  sportName: string;
  facilityId: string;
  onChanged: (booking: Booking) => void;
}) {
  const [mode, setMode] = useState<"view" | "reschedule">("view");
  const [rescheduleDate, setRescheduleDate] = useState("");
  const [slots, setSlots] = useState<TimeSlot[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);
  const [selectedSlot, setSelectedSlot] = useState<TimeSlot | null>(null);
  const [isWorking, setIsWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [paymentState, setPaymentState] = useState<PaymentStatusPanelState | null>(null);
  const [cancelRefundNote, setCancelRefundNote] = useState<string | null>(null);
  const { startCheckout, checkAgain, isProcessing: isPaying } = usePaymentCheckout();

  if (!booking) return null;

  async function payNow() {
    setError(null);
    setPaymentState("processing");
    const result = await startCheckout(
      {
        facilityId,
        sourceType: booking!.customerType === "MEMBER" ? "MEMBER_BOOKING" : "GUEST_BOOKING",
        bookingId: booking!.id,
      },
      {
        description: `${sportName} · ${court?.name ?? "Court"}`,
        prefill: booking!.customerType === "GUEST" ? { name: booking!.guestName ?? undefined, contact: booking!.guestPhone ?? undefined } : undefined,
      },
    );
    setPaymentState(result.status === "cancelled" ? null : result);
    if (result.status === "settled") {
      onChanged({ ...booking!, status: "confirmed", paymentStatus: "PAID" });
    }
  }

  async function handleCheckAgain(paymentOrderId: string) {
    const result: CheckoutResult = await checkAgain(paymentOrderId);
    setPaymentState(result);
    if (result.status === "settled") {
      onChanged({ ...booking!, status: "confirmed", paymentStatus: "PAID" });
    }
  }

  async function loadRescheduleSlots(dateStr: string) {
    if (!court) return;
    setSlotsLoading(true);
    setSelectedSlot(null);
    const date = new Date(`${dateStr}T00:00:00`);
    const dow = date.getDay();
    const [override, facilitySchedule, existing] = await Promise.all([
      getOperatingHoursService().getPlayingAreaSchedule(court.id),
      getOperatingHoursService().getFacilitySchedule(facilityId),
      getBookingService().getBookingsForCourtOnDate(court.id, date),
    ]);
    const schedule = override ?? facilitySchedule;
    const day = schedule?.days.find((d) => d.dayOfWeek === dow) ?? null;
    setSlots(day ? computeAvailableSlots(date, day, existing.filter((b) => b.id !== booking!.id)) : []);
    setSlotsLoading(false);
  }

  async function confirmReschedule() {
    if (!court || !selectedSlot) return;
    setIsWorking(true);
    setError(null);
    try {
      const updated = await getBookingService().rescheduleBooking({
        bookingId: booking!.id,
        courtId: court.id,
        startTime: selectedSlot.startTime,
        endTime: selectedSlot.endTime,
      });
      onChanged(updated);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to reschedule this booking.");
    } finally {
      setIsWorking(false);
    }
  }

  async function cancel() {
    setIsWorking(true);
    setError(null);
    setCancelRefundNote(null);
    try {
      // Server-side (cancel-booking Edge Function): cancels the booking,
      // releases court availability, and — if the booking was paid — requests
      // and submits a cancellation-policy-derived refund, all in one call
      // (spec §8/§13). Never a plain client-side status update anymore.
      const { booking: cancelled, refund } = await getRefundService().cancelBooking({ bookingId: booking!.id, reason: "Owner Request" });
      onChanged(cancelled);
      if (refund) {
        setCancelRefundNote(
          refund.status === "FAILED"
            ? "The booking was cancelled, but the refund could not be submitted. Please retry from Refunds."
            : "Refund requested — it will show as processed once Razorpay confirms it.",
        );
      } else {
        onOpenChange(false);
      }
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to cancel this booking.");
    } finally {
      setIsWorking(false);
    }
  }

  const canModify = booking.status === "pending" || booking.status === "confirmed";

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) setMode("view");
        onOpenChange(next);
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Booking Details</DialogTitle>
        </DialogHeader>

        {mode === "view" ? (
          <div className="space-y-3 text-sm">
            <div>
              <span className="font-medium">{sportName}</span> · {court?.name ?? "Court"}
            </div>
            <div className="text-muted-foreground">
              {new Date(booking.startTime).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}
              {" · "}
              {formatTime(booking.startTime)} – {formatTime(booking.endTime)}
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <p className="text-xs text-muted-foreground">Customer</p>
                <p>{booking.customerType === "GUEST" ? `${booking.guestName} (Guest)` : "Member"}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Amount</p>
                <p>{booking.amountMinor != null ? formatCurrency(booking.amountMinor, booking.currency) : "—"}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Payment</p>
                <p className="capitalize">{booking.paymentStatus.toLowerCase()}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Status</p>
                <p className="capitalize">{booking.status}</p>
              </div>
            </div>
            {paymentState && (
              <PaymentStatusPanel
                state={paymentState}
                settledLabel="Booking Confirmed"
                resourceLabel="booking"
                isCheckingAgain={isPaying}
                onCheckAgain={
                  paymentState !== "processing" && paymentState.status === "pending"
                    ? () => handleCheckAgain(paymentState.paymentOrderId)
                    : undefined
                }
                onRetry={paymentState !== "processing" && paymentState.status === "failed" ? payNow : undefined}
              />
            )}
            {cancelRefundNote && <p className="text-muted-foreground">{cancelRefundNote}</p>}
            {error && <p className="text-destructive">{error}</p>}
          </div>
        ) : (
          <div className="space-y-3 text-sm">
            <input
              aria-label="New date"
              type="date"
              value={rescheduleDate}
              onChange={(e) => {
                setRescheduleDate(e.target.value);
                if (e.target.value) loadRescheduleSlots(e.target.value);
              }}
              className="h-11 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm"
            />
            {slotsLoading ? (
              <p className="text-muted-foreground">Loading availability…</p>
            ) : rescheduleDate && slots.length === 0 ? (
              <p className="text-muted-foreground">No slots available.</p>
            ) : (
              <div className="flex max-h-40 flex-wrap gap-2 overflow-y-auto">
                {slots.map((s) => (
                  <button
                    key={s.startTime}
                    type="button"
                    disabled={!s.available}
                    onClick={() => setSelectedSlot(s)}
                    className={`h-9 rounded-md border px-3 text-xs font-medium ${
                      selectedSlot?.startTime === s.startTime
                        ? "border-primary bg-primary text-primary-foreground"
                        : s.available
                          ? "border-input bg-secondary/60 hover:bg-accent"
                          : "cursor-not-allowed border-input bg-muted text-muted-foreground line-through"
                    }`}
                  >
                    {formatTime(s.startTime)}
                  </button>
                ))}
              </div>
            )}
            {error && <p className="text-destructive">{error}</p>}
          </div>
        )}

        <DialogFooter>
          {mode === "view" ? (
            canModify && (
              <>
                {booking.paymentStatus === "PENDING" && (
                  <Button type="button" onClick={payNow} disabled={isPaying || isWorking}>
                    {isPaying ? "Processing…" : "Pay Now"}
                  </Button>
                )}
                <Button type="button" variant="outline" onClick={() => setMode("reschedule")} disabled={isWorking || isPaying}>
                  Reschedule
                </Button>
                <Button type="button" variant="destructive" onClick={cancel} disabled={isWorking || isPaying}>
                  {isWorking ? "Cancelling…" : "Cancel Booking"}
                </Button>
              </>
            )
          ) : (
            <>
              <Button type="button" variant="ghost" onClick={() => setMode("view")} disabled={isWorking}>
                Back
              </Button>
              <Button type="button" onClick={confirmReschedule} disabled={!selectedSlot || isWorking}>
                {isWorking ? "Saving…" : "Confirm New Time"}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}