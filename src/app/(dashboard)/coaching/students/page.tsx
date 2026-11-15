import type { Metadata } from "next";
import { CoachingStudentsPage } from "@/features/coaching/components/students-page";

export const metadata: Metadata = { title: `Manage Students` };

export default function Page() {
  return <CoachingStudentsPage />;
}
