import type { Metadata } from "next";
import { ProgramWizardPage } from "@/features/coaching/components/program-wizard-page";

export const metadata: Metadata = { title: `Create Program` };

export default function Page() {
  return <ProgramWizardPage />;
}
