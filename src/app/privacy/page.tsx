import type { Metadata } from "next";
import Link from "next/link";
import { LEGAL_CONTACT_EMAIL, LEGAL_CONTACT_PHONE, LEGAL_WEBSITE, LegalPage, type LegalSection } from "@/features/legal/legal-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Privacy Policy — ${APP_NAME}`,
  description: "What GameAll collects, why, who it is shared with, and how to delete your account.",
};

const sections: LegalSection[] = [
  {
    title: "Who we are",
    body: (
      <p>
        GameAll is a club-management service for sports facilities: bookings, memberships, coaching, tournaments and payments. This policy covers the GameAll
        website and the GameAll Venue mobile app. You can reach us at <a className="text-primary hover:underline" href={`mailto:${LEGAL_CONTACT_EMAIL}`}>{LEGAL_CONTACT_EMAIL}</a> or {LEGAL_CONTACT_PHONE}. Website: {LEGAL_WEBSITE}.
      </p>
    ),
  },
  {
    title: "What we collect",
    body: (
      <ul className="list-disc space-y-1.5 pl-5">
        <li><strong>Your account:</strong> name, email address, mobile number and a password (stored only in scrambled form). We verify your email with a one-time code and your mobile number with an automated call.</li>
        <li><strong>Your facility:</strong> its name, address and contact details, sports, courts, opening hours, prices, logo and photos you choose to upload.</li>
        <li><strong>Your customers&apos; details, entered by the facility:</strong> members, guests and coaching students (name, phone, email, address, date of birth, gender and notes, where the facility chooses to enter them), bookings, memberships, enrolments, attendance and payment records.</li>
        <li><strong>Payments:</strong> amounts, status, method and Razorpay reference numbers. Card, UPI and bank details are entered on Razorpay and are not stored by us.</li>
        <li><strong>Payout details:</strong> the bank account or UPI ID a facility gives us to receive its money. GameAll staff see these to verify them.</li>
        <li><strong>Photos:</strong> pictures you take or choose from your phone for a profile, logo, coach or program. The app asks for camera access only when you choose &quot;Take a photo&quot;.</li>
        <li><strong>Device information:</strong> a notification token so we can send push notifications, and basic technical and crash information to keep the app working.</li>
      </ul>
    ),
  },
  {
    title: "How we use it",
    body: (
      <ul className="list-disc space-y-1.5 pl-5">
        <li>To run the service you asked for: bookings, memberships, coaching, finance and reports.</li>
        <li>To take and record payments and to send money to the facility.</li>
        <li>To send notifications such as upcoming bookings, new memberships and payment results. You can switch categories off in Settings.</li>
        <li>To verify accounts, prevent misuse and keep the service secure.</li>
        <li>To fix problems and improve the app.</li>
      </ul>
    ),
  },
  {
    title: "Who we share it with",
    body: (
      <>
        <p>We do not sell personal data. We use these providers to run the service, and they handle data only for that purpose:</p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li><strong>Supabase</strong> — database, sign-in and file storage.</li>
          <li><strong>Razorpay</strong> — online payments and Auto Pay mandates.</li>
          <li><strong>Google Firebase</strong> — push notifications and crash reports.</li>
          <li><strong>Resend</strong> — verification emails.</li>
          <li><strong>2Factor</strong> — automated verification calls.</li>
        </ul>
        <p>Within a facility, an owner decides which staff can see which pages. We may also disclose information when the law requires it.</p>
      </>
    ),
  },
  {
    title: "How long we keep it",
    body: (
      <p>
        We keep your data while your account is active. When you delete your account we delete or anonymise your personal data. We keep payment and tax records for
        as long as the law requires, without the details that identify you where possible.
      </p>
    ),
  },
  {
    title: "Deleting your account and data",
    body: (
      <p>
        In the app, open <strong>Profile → Delete account</strong>. You can also ask from any browser without installing the app on the{" "}
        <Link className="text-primary hover:underline" href="/delete-account">account deletion page</Link>. Deleting removes your sign-in and personal data as described above.
      </p>
    ),
  },
  {
    title: "Security",
    body: (
      <p>
        Data is sent over encrypted connections. Access to each facility&apos;s data is restricted to its owner and the staff the owner has authorised, and enforced in
        the database itself. No system is perfectly secure, so please use a strong password and keep it private.
      </p>
    ),
  },
  {
    title: "Children",
    body: <p>GameAll is for adults who run or visit sports facilities. It is not directed at children under 18, and we do not knowingly collect their data.</p>,
  },
  {
    title: "Your choices and rights",
    body: (
      <p>
        You can see and edit your details in Profile, switch notifications off in Settings, and ask us to correct or delete your data at any time using the contact
        above.
      </p>
    ),
  },
  {
    title: "Changes",
    body: <p>If we change this policy we will update the date at the top and, for important changes, tell you in the app.</p>,
  },
];

export default function PrivacyPage() {
  return (
    <LegalPage
      title="Privacy Policy"
      intro={<p>This explains what information GameAll collects, why, who it is shared with, and the choices you have. It is written to be read, so we have kept it plain.</p>}
      sections={sections}
    />
  );
}
