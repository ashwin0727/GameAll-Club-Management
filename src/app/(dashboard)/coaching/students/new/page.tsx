import type { Metadata } from "next";
import { AddStudentWizardPage } from "@/features/coaching/components/add-student-wizard-page";

export const metadata: Metadata = { title: `Add Student` };

export default function Page() {
  return <AddStudentWizardPage />;
}
