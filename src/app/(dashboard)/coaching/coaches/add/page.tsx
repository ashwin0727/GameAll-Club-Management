import type { Metadata } from "next";
import { AddCoachPage } from "@/features/coaching/components/add-coach-page";

export const metadata: Metadata = { title: `Add Coach` };

export default function Page() {
  return <AddCoachPage />;
}
