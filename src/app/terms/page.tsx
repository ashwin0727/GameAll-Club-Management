import type { Metadata } from "next";
import Link from "next/link";
import { LEGAL_CONTACT_EMAIL, LegalPage, type LegalSection } from "@/features/legal/legal-page";

export const metadata: Metadata = {
  title: `Terms & Conditions`,
  description: "The terms for using GameAll Venue and GameAll Play.",
};

const link = "text-primary hover:underline";

const sections: LegalSection[] = [
  {
    title: "Using GameAll",
    body: (
      <>
        <p>
          By creating an account or using GameAll you agree to these terms. GameAll is made of two apps and a website: <strong>GameAll Venue</strong>, which gives sports
          venues tools to manage bookings, memberships, coaching and payments, and <strong>GameAll Play</strong>, which lets players find those venues, book courts, join
          memberships and coaching, and pay. You must be at least 18 and able to enter a binding agreement. If you use GameAll for a business, you confirm you may bind it.
        </p>
        <p>GameAll is the technology. The venue, not GameAll, provides the court, the coaching and the facility you book.</p>
      </>
    ),
  },
  {
    title: "Your account",
    body: (
      <p>
        Keep your sign-in details and the one-time codes we send you private, and tell us straight away if you think someone else has used them. A venue owner is responsible for
        the staff they add and for what each staff role is allowed to do. Give us accurate information and keep it up to date.
      </p>
    ),
  },
  {
    title: "For players: bookings, memberships and coaching",
    body: (
      <>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>A booking, membership or coaching enrolment is an arrangement between you and the venue. You agree to follow the venue&apos;s rules and to use the facility safely.</li>
          <li>The price, the time and what is included are shown before you pay. A court booking longer than an hour is held for a short time until its advance is paid.</li>
          <li>Cancellations and refunds follow the <Link className={link} href="/refund-policy">Cancellation &amp; Refund Policy</Link>.</li>
          <li>A membership or coaching fee may be paid once or, where the venue offers it, by Auto Pay (a UPI mandate you approve). You can cancel Auto Pay in your UPI app or from the app, and nothing is charged after you cancel.</li>
          <li>Sport carries a risk of injury. Take part only if you are fit to, and follow the venue&apos;s safety instructions.</li>
        </ul>
      </>
    ),
  },
  {
    title: "For venues: plans, free trial and fees",
    body: (
      <>
        <p>
          GameAll is offered to venues on the Basic and Advanced plans. A new venue&apos;s first plan includes a free trial. You approve Auto Pay when you choose a plan, and
          nothing is charged during the trial. After the trial the plan you chose is charged automatically, monthly or yearly, until you cancel or change plan. If a payment
          fails, your venue falls back to the features included in Basic. GameAll does not charge a commission on your bookings; standard payment-gateway charges apply to
          online payments.
        </p>
        <p>Plans are chosen and paid for on the GameAll website, not inside the Android app. Prices and what each plan includes are shown on our <Link className={link} href="/pricing">pricing page</Link> and may change with notice.</p>
      </>
    ),
  },
  {
    title: "Payments",
    body: (
      <p>
        Online payments are processed by Razorpay under its own terms. Money collected for a venue is sent to the bank account or UPI ID the venue has given us and we have
        verified. A venue is responsible for the services it sells to its customers and for how it handles refunds beyond the Cancellation &amp; Refund Policy.
      </p>
    ),
  },
  {
    title: "Your data and your customers' data",
    body: (
      <p>
        You keep ownership of the information you put into GameAll. A venue is responsible for having the right to enter its customers&apos; details and for using them
        lawfully. How we handle personal data is described in our <Link className={link} href="/privacy">Privacy Policy</Link>.
      </p>
    ),
  },
  {
    title: "What you must not do",
    body: (
      <ul className="list-disc space-y-1.5 pl-5">
        <li>Use GameAll for anything unlawful, or to defraud or harm anyone.</li>
        <li>Book courts or enrol with someone else&apos;s details without their permission, or make bookings you do not intend to use to block others.</li>
        <li>Try to access another person&apos;s or venue&apos;s data, or to break or overload the service.</li>
        <li>Copy, resell or reverse-engineer the service, except where the law allows.</li>
      </ul>
    ),
  },
  {
    title: "Availability and changes",
    body: <p>We work to keep GameAll available but cannot promise it will never be interrupted. We may improve or change features, and will give notice of material changes.</p>,
  },
  {
    title: "Ending your account",
    body: (
      <p>
        You can cancel your plan or delete your account at any time (see <Link className={link} href="/delete-account">account deletion</Link>). We may suspend or close an
        account that breaks these terms or puts others at risk.
      </p>
    ),
  },
  {
    title: "Liability",
    body: (
      <p>
        GameAll is provided &quot;as is&quot;. To the extent the law allows, we are not liable for indirect or consequential loss, for loss caused by events outside our
        control, or for what happens at a venue (including injury, or a venue closing or changing its timings). Our total liability for any claim is limited to the fees you paid us in the 12 months before it.
      </p>
    ),
  },
  {
    title: "Law and contact",
    body: (
      <p>
        These terms are governed by the laws of India. Questions or complaints: <a className={link} href={`mailto:${LEGAL_CONTACT_EMAIL}`}>{LEGAL_CONTACT_EMAIL}</a>.
      </p>
    ),
  },
];

export default function TermsPage() {
  return (
    <LegalPage
      title="Terms & Conditions"
      intro={<p>These are the rules for using GameAll Venue and GameAll Play. Please read them before you create an account.</p>}
      sections={sections}
    />
  );
}
