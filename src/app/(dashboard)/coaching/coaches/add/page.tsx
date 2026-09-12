import type { Metadata } from "next";
import { AddCoachPage } from "@/features/coaching/components/add-coach-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Add Coach — ${APP_NAME}` };

export default function Page() {
  return <AddCoachPage />;
}
