// ═══════════════════════════════════════════════════════════════════════════
// The authoritative one-line definition of every KPI Reports shows, rendered
// in an info tooltip beside the figure (spec §53 "Data Definitions"). If a
// formula ever changes, it changes here and in the RPC header comment — the
// two must always agree.
// ═══════════════════════════════════════════════════════════════════════════

export type KpiKey =
  | "totalBookings"
  | "completedBookings"
  | "cancelledBookings"
  | "confirmedBookings"
  | "pendingBookings"
  | "bookingRevenue"
  | "membershipRevenue"
  | "totalRevenue"
  | "totalExpenses"
  | "netRevenue"
  | "outstandingPayments"
  | "courtUtilization"
  | "sportUtilization"
  | "peakHours"
  | "averageBookingValue"
  | "paymentCollectionRate"
  | "activeMembers"
  | "newMemberships"
  | "expiringMemberships"
  | "membershipSessionUtilization"
  | "guestReleased"
  | "guestBooked"
  | "guestRemaining"
  | "guestReleaseRevenue"
  | "guestBookingRevenue";

export const KPI_DEFINITIONS: Record<KpiKey, string> = {
  totalBookings:
    "Every booking whose start time falls in the selected range, all statuses (cancelled shown as its own slice).",
  completedBookings: "Bookings with status COMPLETED in the range.",
  cancelledBookings: "Bookings with status CANCELLED in the range.",
  confirmedBookings: "Bookings with status CONFIRMED in the range.",
  pendingBookings: "Bookings with status PENDING in the range.",
  bookingRevenue:
    "Realised member-booking + guest-booking payments in the range (Finance, cash basis). Unpaid booking amounts are not counted.",
  membershipRevenue:
    "Realised membership payments in the range. Membership session usage is never revenue.",
  totalRevenue:
    "Sum of successfully collected payments in the range (Finance gross revenue). Cash basis — a pending amount is not revenue.",
  totalExpenses: "Recorded facility expenses in the range (Finance). Voided expenses excluded.",
  netRevenue: "Gross revenue minus refunds minus expenses (Finance).",
  outstandingPayments:
    "Money still owed on bookings and memberships that have happened and not been fully paid (Pending Payments).",
  courtUtilization:
    "Booked minutes divided by open (bookable) minutes for the range, capped at 100%. Open minutes come from the court's operating hours; there is no separate maintenance model.",
  sportUtilization: "The same booked-over-open ratio, summed across all courts of one sport.",
  peakHours:
    "For each hour of day: booked minutes divided by the minutes the facility is open in that hour, over the range. Closed hours are excluded, not shown as zero demand.",
  averageBookingValue:
    "Total captured value of paid, non-cancelled guest bookings in the range, divided by their count. Unpaid and cancelled bookings are excluded from both.",
  paymentCollectionRate:
    "Collected amount divided by (collected + outstanding) for the range. Pending payments are not counted as collected.",
  activeMembers: "Memberships with status ACTIVE as of now, for this facility.",
  newMemberships: "Memberships created within the selected range.",
  expiringMemberships: "Active memberships whose end date is within the next 30 days.",
  membershipSessionUtilization:
    "Confirmed member + guest slots divided by total session capacity, over sessions dated in the range.",
  guestReleased:
    "Total guest capacity the owner released across sessions dated in the range.",
  guestBooked: "Confirmed guest bookings against released capacity, over sessions in the range.",
  guestRemaining: "Released capacity minus guest bookings.",
  guestReleaseRevenue:
    "Realised payments for released-seat guest bookings, classified as guest-booking revenue by Finance.",
  guestBookingRevenue:
    "Realised payments for guest bookings (both ad-hoc and released-seat) in the range.",
};

export const FRESHNESS_NOTE =
  "Reports are real-time — every figure is read live from Bookings, Memberships and Finance when the page loads. There is no cached or delayed data.";
