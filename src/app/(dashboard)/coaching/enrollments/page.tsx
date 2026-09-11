import type { Metadata } from "next";
import { EnrollmentsPage } from "@/features/coaching/components/enrollments-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Student Enrollments — ${APP_NAME}` };

export default function Page() {
  return <EnrollmentsPage />;
}
