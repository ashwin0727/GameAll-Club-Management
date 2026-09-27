import type { Metadata } from "next";
import { CoachingStudentsPage } from "@/features/coaching/components/students-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Manage Students — ${APP_NAME}` };

export default function Page() {
  return <CoachingStudentsPage />;
}
