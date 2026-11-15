import type { Metadata } from "next";
import { SessionsPage } from "@/features/coaching/components/sessions-page";

export const metadata: Metadata = { title: `Coach Scheduler` };

export default function Page() {
  return <SessionsPage />;
}
