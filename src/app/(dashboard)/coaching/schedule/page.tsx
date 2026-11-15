import type { Metadata } from "next";
import { SchedulePage } from "@/features/coaching/components/schedule-page";

export const metadata: Metadata = { title: `Coaching Schedule` };

export default function Page() {
  return <SchedulePage />;
}
