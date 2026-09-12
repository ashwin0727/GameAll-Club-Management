import type { Metadata } from "next";
import { CoachesPage } from "@/features/coaching/components/coaches-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Coaches — ${APP_NAME}` };

export default function Page() {
  return <CoachesPage />;
}
