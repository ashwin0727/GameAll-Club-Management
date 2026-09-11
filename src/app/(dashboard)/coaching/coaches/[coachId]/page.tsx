import type { Metadata } from "next";
import { CoachDetailsPage } from "@/features/coaching/components/coach-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Coach — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ coachId: string }> }) {
  const { coachId } = await params;
  return <CoachDetailsPage coachId={coachId} />;
}
