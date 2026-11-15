import type { Metadata } from "next";
import { CoachesPage } from "@/features/coaching/components/coaches-page";

export const metadata: Metadata = { title: `Coaches` };

export default function Page() {
  return <CoachesPage />;
}
