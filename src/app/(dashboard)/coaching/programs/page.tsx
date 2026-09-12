import type { Metadata } from "next";
import { ProgramsPage } from "@/features/coaching/components/programs-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Coaching Programs — ${APP_NAME}` };

export default function Page() {
  return <ProgramsPage />;
}
