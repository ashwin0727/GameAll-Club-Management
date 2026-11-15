import type { Metadata } from "next";
import { CoachingOverviewPage } from "@/features/coaching/components/overview-page";

export const metadata: Metadata = { title: `Coaching` };

export default function Page() {
  return <CoachingOverviewPage />;
}
