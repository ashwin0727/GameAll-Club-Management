import type { Metadata } from "next";
import { SessionWizardPage } from "@/features/coaching/components/session-wizard-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `New Session — ${APP_NAME}` };

export default function Page() {
  return <SessionWizardPage />;
}
