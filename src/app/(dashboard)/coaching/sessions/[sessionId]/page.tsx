import type { Metadata } from "next";
import { SessionDetailsPage } from "@/features/coaching/components/session-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Session — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ sessionId: string }> }) {
  const { sessionId } = await params;
  return <SessionDetailsPage sessionId={sessionId} />;
}
