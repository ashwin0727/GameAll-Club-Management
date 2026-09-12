import type { Metadata } from "next";
import { ProgramWizardPage } from "@/features/coaching/components/program-wizard-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Create Program — ${APP_NAME}` };

export default function Page() {
  return <ProgramWizardPage />;
}
