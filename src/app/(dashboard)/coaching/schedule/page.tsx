import type { Metadata } from "next";
import { SchedulePage } from "@/features/coaching/components/schedule-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Coaching Schedule — ${APP_NAME}` };

export default function Page() {
  return <SchedulePage />;
}
