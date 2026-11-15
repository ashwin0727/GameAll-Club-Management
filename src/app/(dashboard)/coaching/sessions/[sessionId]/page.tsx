import type { Metadata } from "next";
import { SessionDetailsPage } from "@/features/coaching/components/session-details-page";

export const metadata: Metadata = { title: `Session` };

export default async function Page({ params }: { params: Promise<{ sessionId: string }> }) {
  const { sessionId } = await params;
  return <SessionDetailsPage sessionId={sessionId} />;
}
