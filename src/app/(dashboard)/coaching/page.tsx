import type { Metadata } from "next";
import { CoachingOverviewPage } from "@/features/coaching/components/overview-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Coaching — ${APP_NAME}` };

export default function Page() {
  return <CoachingOverviewPage />;
}
