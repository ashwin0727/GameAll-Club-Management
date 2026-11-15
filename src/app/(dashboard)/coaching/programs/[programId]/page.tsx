import type { Metadata } from "next";
import { ProgramDetailsPage } from "@/features/coaching/components/program-details-page";

export const metadata: Metadata = { title: `Program` };

export default async function Page({ params }: { params: Promise<{ programId: string }> }) {
  const { programId } = await params;
  return <ProgramDetailsPage programId={programId} />;
}
