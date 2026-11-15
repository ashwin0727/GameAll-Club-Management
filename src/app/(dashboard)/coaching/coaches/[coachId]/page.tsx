import type { Metadata } from "next";
import { CoachDetailsPage } from "@/features/coaching/components/coach-details-page";

export const metadata: Metadata = { title: `Coach` };

export default async function Page({ params }: { params: Promise<{ coachId: string }> }) {
  const { coachId } = await params;
  return <CoachDetailsPage coachId={coachId} />;
}
