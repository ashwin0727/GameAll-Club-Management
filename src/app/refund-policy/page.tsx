import type { Metadata } from "next";
import Link from "next/link";
import { LEGAL_CONTACT_EMAIL, LegalPage, type LegalSection } from "@/features/legal/legal-page";

export const metadata: Metadata = {
  title: `Cancellation & Refund Policy`,
  description: "How cancelling a GameAll court booking, membership or coaching enrolment works, and how refunds are returned.",
};

const link = "text-primary hover:underline";

// The same schedule the database applies (cancellation_deduction_percent, migration 0188) and the Play app shows before a player pays.
const REFUND_SCHEDULE: ReadonlyArray<readonly [string, number]> = [
  ["12 hours or more before the start", 5],
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
  ["Less than 1 hour, or after the start", 100],
];

const sections: LegalSection[] = [
  {
    title: "Court bookings you have paid in full",
    body: (
      <>
        <p>You can cancel a court booking in GameAll Play under <strong>My bookings</strong>. Before you confirm, the app shows exactly what you will get back. The amount kept depends on how long is left before the booking starts:</p>
        <div className="overflow-hidden rounded-lg border border-border">
          <table className="w-full text-left text-sm">
            <thead className="bg-muted/50">
              <tr>
                <th className="px-4 py-2 font-semibold">Time left before the start</th>
                <th className="px-4 py-2 font-semibold">Kept as a cancellation charge</th>
                <th className="px-4 py-2 font-semibold">Refunded to you</th>
              </tr>
            </thead>
            <tbody>
              {REFUND_SCHEDULE.map(([when, kept]) => (
                <tr key={when} className="border-t border-border">
                  <td className="px-4 py-2">{when}</td>
                  <td className="px-4 py-2">{kept}%</td>
                  <td className="px-4 py-2">{100 - kept}%</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </>
    ),
  },
  {
    title: "Bookings where only the advance is paid",
    body: (
      <p>
        A court booking longer than an hour can be secured with a 50% advance. If you cancel a booking that is only part-paid, the advance is not refunded, unless the venue
        chooses to refund it. Pay in full if you want the schedule above to apply. A booking you never paid for can be cancelled at no cost.
      </p>
    ),
  },
  {
    title: "How refunds are returned",
    body: (
      <ul className="list-disc space-y-1.5 pl-5">
        <li>Money you paid online goes back to the same UPI app, card or bank account it came from, through Razorpay. Your bank usually credits it within 5 to 7 working days.</li>
        <li>If part of the booking was paid in cash at the venue, that part is refunded by the venue, and the app tells you so.</li>
        <li>If the venue cancels or cannot provide the court, the venue refunds what you paid. If that does not happen, write to us and we will follow it up.</li>
      </ul>
    ),
  },
  {
    title: "Memberships and coaching",
    body: (
      <ul className="list-disc space-y-1.5 pl-5">
        <li>Each venue sets its own membership and coaching terms, shown on the plan or programme before you pay. Fees for a period already started are normally not refundable.</li>
        <li>If you joined by Auto Pay you can stop future charges at any time from your UPI app or from GameAll Play; nothing is charged after you cancel. A charge already made is not reversed automatically.</li>
        <li>If you were charged by mistake, or twice, write to us and we will sort it out with the venue and Razorpay.</li>
      </ul>
    ),
  },
  {
    title: "If something went wrong",
    body: (
      <p>
        If money left your account but your booking or membership did not appear, do not pay again. It is normally settled automatically within a few minutes; if it is not,
        write to <a className={link} href={`mailto:${LEGAL_CONTACT_EMAIL}`}>{LEGAL_CONTACT_EMAIL}</a> with your phone number and the time of payment and we will fix it or refund you. See also the{" "}
        <Link className={link} href="/terms">Terms &amp; Conditions</Link>.
      </p>
    ),
  },
];

export default function RefundPolicyPage() {
  return (
    <LegalPage
      title="Cancellation & Refund Policy"
      intro={<p>How cancelling works in GameAll Play, and how and when refunds are returned. It is the same schedule the app shows you before you confirm.</p>}
      sections={sections}
    />
  );
}
