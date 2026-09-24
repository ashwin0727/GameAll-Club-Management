import { describe, expect, it } from "vitest";
import type { EnrollmentRow } from "@/features/coaching/types";
import type { MembershipListRow } from "@/features/memberships/types";
import { daysPattern, enrollmentToRow, formatMonths, hoursLabel, membershipToRow, monthsBetween } from "@/features/bookings/list-sources";

const courts = [
  { id: "c1", name: "Court 1" },
  { id: "c2", name: "Court 2" },
];

function membership(over: Partial<MembershipListRow> = {}): MembershipListRow {
  return {
    membershipId: "aaaa1111-0000-0000-0000-000000000000",
    memberId: "m1",
    memberName: "Rahul Mehta",
    memberPhone: "+91 98765 43210",
    memberEmail: null,
    planId: "p1",
    planName: "Monthly Membership",
    monthlyPriceInr: 1500,
    status: "active",
    startDate: "2026-09-01",
    endDate: "2026-09-30",
    slot: { name: "Batch 1", daysOfWeek: [1, 3, 5], startTime: "05:00:00", endTime: "06:00:00", courtName: "Court 1" },
    ...over,
  };
}

function enrollment(over: Partial<EnrollmentRow> = {}): EnrollmentRow {
  return {
    id: "bbbb2222-0000-0000-0000-000000000000",
    memberId: "m2",
    studentName: "Neha Kapoor",
    studentPhone: "+91 91234 56789",
    programId: "pr1",
    programName: "Junior Camp",
    coachName: "Arjun",
    startDate: "2026-09-01",
    endDate: "2026-10-31",
    sessionsTotal: 12,
    priceMinor: 600000,
    paidMinor: 600000,
    status: "ACTIVE",
    paymentStatus: "PAID",
    ...over,
  };
}

describe("monthsBetween / formatMonths", () => {
  it("reads a monthly membership as 1 Month and a quarterly one as 3 Months", () => {
    expect(formatMonths(monthsBetween("2026-09-01", "2026-09-30"))).toBe("1 Month");
    expect(formatMonths(monthsBetween("2026-09-01", "2026-10-01"))).toBe("1 Month");
    expect(formatMonths(monthsBetween("2026-09-01", "2026-11-30"))).toBe("3 Months");
    expect(formatMonths(monthsBetween("2026-09-01", "2027-08-31"))).toBe("12 Months");
  });
  it("never goes below one month", () => {
    expect(monthsBetween("2026-09-01", "2026-09-05")).toBe(1);
    expect(monthsBetween("2026-09-01", "2026-09-01")).toBe(1);
  });
});

describe("daysPattern", () => {
  it("names the common patterns", () => {
    expect(daysPattern([1, 2, 3, 4, 5])).toBe("Weekdays");
    expect(daysPattern([6, 0])).toBe("Weekends");
    expect(daysPattern([0, 1, 2, 3, 4, 5, 6])).toBe("Every day");
    expect(daysPattern([5, 1, 3])).toBe("Mon · Wed · Fri");
    expect(daysPattern([])).toBe("");
  });
});

describe("hoursLabel", () => {
  it("is compact", () => {
    expect(hoursLabel(720)).toBe("12 hrs");
    expect(hoursLabel(90)).toBe("1.5 hrs");
    expect(hoursLabel(60)).toBe("1 hr");
  });
});

describe("membershipToRow", () => {
  it("monthly: 1 Month, the monthly price as the amount, days and time under the date", () => {
    const r = membershipToRow(membership(), courts);
    expect(r).toMatchObject({
      kind: "MEMBERSHIP",
      durationLabel: "1 Month",
      durationSub: "Monthly Membership",
      amountMinor: 150000,
      amountSub: null,
      status: "confirmed",
      statusLabel: "Active",
      courtIds: ["c1"],
      href: "/memberships/aaaa1111-0000-0000-0000-000000000000",
    });
    expect(r.timeLabel).toBe("Mon · Wed · Fri · 5:00 AM – 6:00 AM");
    expect(r.reference).toBe("MEMAAAA");
  });

  it("quarterly: 3 Months, the total for the quarter, with the monthly price noted", () => {
    const r = membershipToRow(membership({ endDate: "2026-11-30", planName: "Quarterly" }), courts);
    expect(r.durationLabel).toBe("3 Months");
    expect(r.amountMinor).toBe(450000);
    expect(r.amountSub).toBe("₹1,500 / month");
  });

  it("maps payment-incomplete and inactive memberships to Pending and Cancelled buckets, keeping their own wording", () => {
    expect(membershipToRow(membership({ status: "payment_incomplete" }), courts)).toMatchObject({ status: "pending", statusLabel: "Payment pending" });
    expect(membershipToRow(membership({ status: "inactive" }), courts)).toMatchObject({ status: "cancelled", statusLabel: "Inactive" });
  });

  it("copes with a membership that has no batch slot", () => {
    const r = membershipToRow(membership({ slot: null }), courts);
    expect(r.courtIds).toEqual([]);
    expect(r.timeLabel).toBe("Plan: Monthly Membership");
  });
});

describe("enrollmentToRow", () => {
  const schedule = { sessionMinutes: 60, days: [1, 2, 3, 4, 5], courtIds: ["c2"] };

  it("shows sessions, total hours and the weekday pattern, with the fee and its payment state", () => {
    const r = enrollmentToRow(enrollment(), schedule);
    expect(r).toMatchObject({
      kind: "COACHING",
      durationLabel: "12 Sessions",
      durationSub: "12 hrs · Weekdays",
      amountMinor: 600000,
      amountSub: "Paid in full",
      status: "confirmed",
      statusLabel: "Active",
      courtIds: ["c2"],
      href: "/coaching/enrollments/bbbb2222-0000-0000-0000-000000000000",
    });
    expect(r.timeLabel).toBe("Junior Camp · Coach Arjun");
  });

  it("recognises a weekend program and a partly paid fee", () => {
    const r = enrollmentToRow(enrollment({ paymentStatus: "PARTIAL", paidMinor: 200000 }), { ...schedule, days: [6, 0] });
    expect(r.durationSub).toBe("12 hrs · Weekends");
    expect(r.amountSub).toBe("Paid ₹2,000");
  });

  it("handles an open-ended program and unknown schedule without inventing details", () => {
    const r = enrollmentToRow(enrollment({ sessionsTotal: null, paymentStatus: "PENDING", paidMinor: 0 }), undefined);
    expect(r.durationLabel).toBe("Ongoing");
    expect(r.durationSub).toBeNull();
    expect(r.amountSub).toBe("Payment pending");
    expect(r.courtIds).toEqual([]);
  });

  it("marks membership-included coaching as such and maps every status", () => {
    expect(enrollmentToRow(enrollment({ paymentStatus: "INCLUDED", priceMinor: 0 }), schedule).amountSub).toBe("Included in membership");
    expect(enrollmentToRow(enrollment({ status: "PAUSED" }), schedule)).toMatchObject({ status: "pending", statusLabel: "Paused" });
    expect(enrollmentToRow(enrollment({ status: "COMPLETED" }), schedule).status).toBe("completed");
    expect(enrollmentToRow(enrollment({ status: "CANCELLED" }), schedule).status).toBe("cancelled");
  });
});
