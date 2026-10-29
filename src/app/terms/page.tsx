import type { Metadata } from "next";
import Link from "next/link";
import { LEGAL_CONTACT_EMAIL, LegalPage, type LegalSection } from "@/features/legal/legal-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Terms of Service — ${APP_NAME}`,
  description: "The terms for using GameAll.",
};

const sections: LegalSection[] = [
  {
    title: "Using GameAll",
    body: (
      <p>
        By creating an account or using GameAll you agree to these terms. GameAll gives sports facilities tools to manage bookings, memberships, coaching,
        tournaments and payments. You must be at least 18 and able to enter a binding agreement. If you use GameAll for a business, you confirm you may bind it.
      </p>
    ),
  },
  {
    title: "Your account",
    body: (
      <p>
        Keep your sign-in details private and tell us straight away if you think someone else has used them. An owner is responsible for the staff they add and for
        what each staff role is allowed to do. Give us accurate information and keep it up to date.
      </p>
    ),
  },
  {
    title: "Plans, free trial and fees",
    body: (
      <>
        <p>
          GameAll is offered on the Basic and Advanced plans. A new facility&apos;s first plan includes a free trial. You approve Auto Pay when you choose a plan, and
          nothing is charged during the trial. After the trial the plan you chose is charged automatically, monthly or yearly, until you cancel or change plan. If a
          payment fails, your facility falls back to the features included in Basic. GameAll does not charge a commission on your bookings; standard payment-gateway charges
          apply to online payments.
        </p>
        <p>Prices and what each plan includes are shown on our <Link className="text-primary hover:underline" href="/pricing">pricing page</Link> and may change with notice.</p>
      </>
    ),
  },
  {
    title: "Payments from your customers",
    body: (
      <p>
        Online payments are processed by Razorpay under its own terms. Money collected for a facility is sent to the bank account or UPI ID the facility has given us and
        we have verified. Refunds, cancellations and the services you sell to your customers are your responsibility.
      </p>
    ),
  },
  {
    title: "Your data and your customers&apos; data",
    body: (
      <p>
        You keep ownership of the information you put into GameAll. You are responsible for having the right to enter your customers&apos; details and for using them
        lawfully. How we handle personal data is described in our <Link className="text-primary hover:underline" href="/privacy">Privacy Policy</Link>.
      </p>
    ),
  },
  {
    title: "What you must not do",
    body: (
      <ul className="list-disc space-y-1.5 pl-5">
        <li>Use GameAll for anything unlawful, or to defraud or harm anyone.</li>
        <li>Try to access another facility&apos;s data, or to break or overload the service.</li>
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
        You can cancel your plan or delete your account at any time (see <Link className="text-primary hover:underline" href="/delete-account">account deletion</Link>). We may suspend
        or close an account that breaks these terms or puts others at risk.
      </p>
    ),
  },
  {
    title: "Liability",
    body: (
      <p>
        GameAll is provided &quot;as is&quot;. To the extent the law allows, we are not liable for indirect or consequential loss, or for loss caused by events outside our
        control, and our total liability for any claim is limited to the fees you paid us in the 12 months before it.
      </p>
    ),
  },
  {
    title: "Law and contact",
    body: (
      <p>
        These terms are governed by the laws of India. Questions: <a className="text-primary hover:underline" href={`mailto:${LEGAL_CONTACT_EMAIL}`}>{LEGAL_CONTACT_EMAIL}</a>.
      </p>
    ),
  },
];

export default function TermsPage() {
  return (
    <LegalPage
      title="Terms of Service"
      intro={<p>These are the rules for using GameAll. Please read them before you create an account.</p>}
      sections={sections}
    />
  );
}
