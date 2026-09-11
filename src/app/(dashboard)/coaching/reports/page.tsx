import type { Metadata } from "next";
import { CoachingReportsPage } from "@/features/coaching/components/reports-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Coaching Reports — ${APP_NAME}` };

export default function Page() {
  return <CoachingReportsPage />;
}
