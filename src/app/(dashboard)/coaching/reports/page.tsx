import type { Metadata } from "next";
import { CoachingReportsPage } from "@/features/coaching/components/reports-page";

export const metadata: Metadata = { title: `Coaching Reports` };

export default function Page() {
  return <CoachingReportsPage />;
}
