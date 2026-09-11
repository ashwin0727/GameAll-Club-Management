import type { Metadata } from "next";
import { ProgramDetailsPage } from "@/features/coaching/components/program-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Program — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ programId: string }> }) {
  const { programId } = await params;
  return <ProgramDetailsPage programId={programId} />;
}
