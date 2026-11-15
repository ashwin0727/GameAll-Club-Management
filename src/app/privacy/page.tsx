import type { Metadata } from "next";
import Link from "next/link";
import { LEGAL_CONTACT_EMAIL, LEGAL_CONTACT_PHONE, LEGAL_WEBSITE, LegalPage, type LegalSection } from "@/features/legal/legal-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Privacy Policy — ${APP_NAME}`,
  description: "What GameAll collects in the Venue app, the Play app and on the website, why, who it is shared with, and how to delete your account.",
};

const link = "text-primary hover:underline";

const sections: LegalSection[] = [
  {
    title: "Who we are and what this covers",
    body: (
      <>
        <p>
          GameAll is a service for sports venues and the people who play at them: bookings, memberships, coaching and payments. This one policy covers all of it:
        </p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li><strong>GameAll Venue</strong> — the app (and website) a venue owner or staff member uses to run the venue.</li>
          <li><strong>GameAll Play</strong> — the app (and website) a player uses to find venues, book courts, join memberships and coaching, and pay.</li>
          <li>The public booking and membership pages a venue shares with its customers.</li>
        </ul>
        <p>
          Contact us at <a className={link} href={`mailto:${LEGAL_CONTACT_EMAIL}`}>{LEGAL_CONTACT_EMAIL}</a> or {LEGAL_CONTACT_PHONE}. Website: {LEGAL_WEBSITE}.
          If you have a concern about your data you can write to the same address and we will reply within 7 days.
        </p>
      </>
    ),
  },
  {
    title: "What we collect",
    body: (
      <>
        <p><strong>If you are a player (GameAll Play)</strong></p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li><strong>Your account:</strong> your mobile number (it is your sign-in, verified with a one-time code by SMS), your name and, if you choose to give it, your email address.</li>
          <li><strong>What you do in the app:</strong> the bookings you make, memberships and coaching programmes you join, their schedules and attendance, and the payments and refunds that go with them.</li>
          <li><strong>Payments:</strong> amounts, status, method and Razorpay reference numbers. Card, UPI and bank details are entered on Razorpay&apos;s secure screen and are never seen or stored by us.</li>
          <li><strong>Location (only if you allow it):</strong> the app can use your phone&apos;s approximate location to pick your city and show the nearest venues first. The position is used on your phone to sort the list. It is not sent to us or stored.</li>
          <li><strong>Notifications:</strong> a notification token for your phone, so we can tell you about bookings, payments and reminders.</li>
        </ul>
        <p><strong>If you run or work at a venue (GameAll Venue)</strong></p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li><strong>Your account:</strong> name, email address, mobile number and a password (stored only in scrambled form). We verify your email with a one-time code and your mobile number with an automated call or SMS.</li>
          <li><strong>Your venue:</strong> its name, address and contact details, sports, courts, opening hours, prices, logo and photos you choose to upload.</li>
          <li><strong>Your customers&apos; details, entered by the venue:</strong> members, guests and coaching students (name, phone, email, address, date of birth, gender and notes, where the venue chooses to enter them), bookings, memberships, enrolments, attendance and payment records.</li>
          <li><strong>Payout details:</strong> the bank account or UPI ID a venue gives us to receive its money. GameAll staff see these to verify them.</li>
          <li><strong>Photos:</strong> pictures you take or choose from your phone for a profile, logo, coach or programme. The app asks for camera or photo access only when you choose to add one.</li>
        </ul>
        <p><strong>In both apps</strong></p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li><strong>Technical information:</strong> basic device and crash information so we can keep the apps working and fix faults.</li>
        </ul>
      </>
    ),
  },
  {
    title: "How we use it",
    body: (
      <ul className="list-disc space-y-1.5 pl-5">
        <li>To run the service you asked for: bookings, memberships, coaching, finance and reports.</li>
        <li>To take and record payments, to refund them under the <Link className={link} href="/refund-policy">cancellation and refund policy</Link>, and to send the venue its money.</li>
        <li>To send notifications such as upcoming bookings, payment results and reminders. You can switch categories off in Settings.</li>
        <li>To verify accounts, prevent misuse and keep the service secure.</li>
        <li>To fix problems and improve the apps.</li>
      </ul>
    ),
  },
  {
    title: "What a venue can see about you",
    body: (
      <p>
        When you book, join a membership or enrol in coaching at a venue, that venue sees your name, mobile number, the booking or enrolment and what you paid, so
        it can serve you. The venue is responsible for how it uses that information. Other venues cannot see it.
      </p>
    ),
  },
  {
    title: "Who we share it with",
    body: (
      <>
        <p>We do not sell personal data and we do not show advertising. We use these providers to run the service, and they handle data only for that purpose:</p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li><strong>Supabase</strong> — database, sign-in and file storage.</li>
          <li><strong>Razorpay</strong> — online payments, refunds and Auto Pay mandates.</li>
          <li><strong>Google Firebase</strong> — push notifications and crash reports.</li>
          <li><strong>Resend</strong> — verification emails.</li>
          <li><strong>2Factor</strong> — one-time codes by SMS and automated calls.</li>
        </ul>
        <p>Within a venue, an owner decides which staff can see which pages. We may also disclose information when the law requires it.</p>
      </>
    ),
  },
  {
    title: "How long we keep it",
    body: (
      <p>
        We keep your data while your account is active. When you delete your account we delete or anonymise your personal data. We keep payment and tax records for
        as long as the law requires, without the details that identify you where possible. A venue&apos;s own booking and attendance records about its customers stay with
        the venue.
      </p>
    ),
  },
  {
    title: "Deleting your account and data",
    body: (
      <p>
        In GameAll Play open <strong>Profile → Support &amp; Legal → Delete my account</strong>; in GameAll Venue open <strong>Profile → Delete account</strong>. You can also
        ask from any browser without installing an app on the{" "}
        <Link className={link} href="/delete-account">account deletion page</Link>. Deleting removes your sign-in and personal data as described above, and cancels any Auto Pay
        so nobody is charged again.
      </p>
    ),
  },
  {
    title: "Security",
    body: (
      <p>
        Data is sent over encrypted connections. Access to each venue&apos;s data is restricted to its owner and the staff the owner has authorised, and enforced in the
        database itself. The apps do not copy your sign-in to cloud backups. No system is perfectly secure, so please keep your password and the codes we send you private.
      </p>
    ),
  },
  {
    title: "Children",
    body: <p>GameAll is for adults who run or visit sports venues. It is not directed at children under 18, and we do not knowingly collect their data.</p>,
  },
  {
    title: "Your choices and rights",
    body: (
      <p>
        You can see and edit your details in Profile, switch notifications off in Settings, withdraw location access in your phone&apos;s settings at any time, and ask us to
        correct or delete your data using the contact above. Under Indian data-protection law you may also ask what we hold about you and complain to us about how it is handled.
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
      intro={<p>This explains what information GameAll collects, why, who it is shared with, and the choices you have. It applies to GameAll Venue and GameAll Play alike. We have kept it plain.</p>}
      sections={sections}
    />
  );
}
