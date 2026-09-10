import type { Metadata } from "next";
import { SessionsPage } from "@/features/coaching/components/sessions-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Coaching Sessions — ${APP_NAME}` };

export default function Page() {
  return <SessionsPage />;
}
