import type { Metadata } from "next";
import Link from "next/link";
import { DeleteAccountPanel } from "@/features/account/delete-account";
import { LEGAL_CONTACT_EMAIL, LegalPage, type LegalSection } from "@/features/legal/legal-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Delete your account — ${APP_NAME}`,
  description: "How to delete your GameAll account and the data linked to it.",
};

const subject = encodeURIComponent("Delete my GameAll account");
const body = encodeURIComponent("Please delete my GameAll account.\n\nThe email address or phone number on the account:\n");

const sections: LegalSection[] = [
  {
    title: "From the app (quickest)",
    body: (
      <ol className="list-decimal space-y-1.5 pl-5">
        <li>Open the GameAll Venue app and sign in.</li>
        <li>Go to <strong>Profile</strong>.</li>
        <li>Choose <strong>Delete account</strong> and confirm.</li>
      </ol>
    ),
  },
  {
    title: "Without the app",
    body: (
      <p>
        Email{" "}
        <a className="text-primary hover:underline" href={`mailto:${LEGAL_CONTACT_EMAIL}?subject=${subject}&body=${body}`}>
          {LEGAL_CONTACT_EMAIL}
        </a>{" "}
        from the email address on your account (or tell us the phone number on it). We confirm it is you, then delete the account and reply when it is done.
      </p>
    ),
  },
  {
    title: "What is deleted",
    body: (
      <ul className="list-disc space-y-1.5 pl-5">
        <li>Your sign-in, profile (name, email, phone, photo) and notification settings.</li>
        <li>If you are a facility owner: the facility and the members, bookings, memberships and coaching records stored for it. Download anything you need first, because this cannot be undone.</li>
        <li>If you are a staff member: your access. The facility keeps its own records of what you did.</li>
      </ul>
    ),
  },
  {
    title: "What we keep",
    body: (
      <p>
        Only one thing delays a deletion: online payments that have not yet been settled to you. We keep those payment records and close your account straight away, and
        everything else is deleted automatically once they are settled. Any plan or Auto Pay is cancelled right away so nobody is charged again. See the{" "}
        <Link className="text-primary hover:underline" href="/privacy">Privacy Policy</Link> for more.
      </p>
    ),
  },
];

export default function DeleteAccountPage() {
  return (
    <LegalPage
      title="Delete your account"
      intro={
        <>
          <p>You can delete your GameAll account and the personal data linked to it at any time. Here is how.</p>
          <DeleteAccountPanel />
        </>
      }
      sections={sections}
    />
  );
}
