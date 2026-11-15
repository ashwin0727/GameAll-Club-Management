import type { Metadata } from "next";
import { ProgramsPage } from "@/features/coaching/components/programs-page";

export const metadata: Metadata = { title: `Coaching Programs` };

export default function Page() {
  return <ProgramsPage />;
}
