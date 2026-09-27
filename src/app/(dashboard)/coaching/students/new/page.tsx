import type { Metadata } from "next";
import { AddStudentWizardPage } from "@/features/coaching/components/add-student-wizard-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Add Student — ${APP_NAME}` };

export default function Page() {
  return <AddStudentWizardPage />;
}
