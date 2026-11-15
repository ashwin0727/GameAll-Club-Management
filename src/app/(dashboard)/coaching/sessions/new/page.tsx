import type { Metadata } from "next";
import { SessionWizardPage } from "@/features/coaching/components/session-wizard-page";

export const metadata: Metadata = { title: `Schedule Session` };

export default function Page() {
  return <SessionWizardPage />;
}
