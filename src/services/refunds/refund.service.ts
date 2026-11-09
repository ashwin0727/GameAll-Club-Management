import type { Booking } from "@/features/bookings/types";
import type {
  BookingCancellationQuote,
  BookingCancellationSummary,
  OfflineRefundDue,
  CancelBookingInput,
  CancelMembershipInput,
  CancelMembershipSlotInput,
  CancellationPolicy,
  InitiateRefundInput,
  Refund,
  RefundListFilters,
  RefundSubmission,
  SettlementException,
  SettlementExceptionListFilters,
  UpsertCancellationPolicyInput,
} from "@/features/refunds/types";

export interface RefundService {
  /** Cancels a `bookings` row (member or ad-hoc guest booking). Court availability releases for free (0001's exclusion constraint); if the booking was paid, a policy-derived refund is requested and submitted to Razorpay in the same call. */
  cancelBooking(input: CancelBookingInput): Promise<{ booking: Booking; refund: RefundSubmission | null; refunds: RefundSubmission[]; cancellation: BookingCancellationSummary | null }>;
  /** What cancelling this booking now would do: hours left, % deducted, refund, and the sentence to show. With `overridePercent`, what the owner's own refund % would do. */
  bookingCancellationQuote(bookingId: string, overridePercent?: number): Promise<BookingCancellationQuote | null>;
  /** Cancels a released-capacity guest booking (membership_session_bookings row). Guest capacity releases for free. */
  cancelMembershipSlot(input: CancelMembershipSlotInput): Promise<{ refund: RefundSubmission | null }>;
  /** Cancels a membership. Refund amount (if any) is an explicit owner/manager decision — never policy/time-derived. The caller refetches membership state (same pattern as assign/renew — no fabricated object here). */
  cancelMembership(input: CancelMembershipInput): Promise<{ refund: RefundSubmission | null }>;
  /** The owner's manual "Initiate Refund" entry point — a partial/manual refund on any settled payment, or resolving a SETTLEMENT_EXCEPTION with a full refund. */
  initiateRefund(input: InitiateRefundInput): Promise<RefundSubmission>;
  /** Captured Amount − Processed Refunds − In-flight Refunds — the server-authoritative ceiling for any refund UI ever shows. */
  refundableAmount(paymentOrderId: string): Promise<number>;
  listRefunds(facilityId: string, filters?: RefundListFilters): Promise<Refund[]>;
  /** Cash refunds the club still owes for cancelled bookings. */
  listOfflineRefundsDue(facilityId: string): Promise<OfflineRefundDue[]>;
  /** The club handed the cash back: closes the item. */
  settleOfflineRefund(bookingId: string): Promise<void>;
  listSettlementExceptions(facilityId: string, filters?: SettlementExceptionListFilters): Promise<SettlementException[]>;
  getCancellationPolicy(facilityId: string): Promise<CancellationPolicy>;
  upsertCancellationPolicy(input: UpsertCancellationPolicyInput): Promise<CancellationPolicy>;
}