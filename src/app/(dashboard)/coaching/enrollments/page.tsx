import type { Metadata } from "next";
import { EnrollmentsPage } from "@/features/coaching/components/enrollments-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Student Enrollments — ${APP_NAME}` };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function Page({ searchParams }: { searchParams: Promise<{ programId?: string | string[] }> }) {
  const { programId } = await searchParams;
  // Only a well-formed id reaches the query — anything else just shows every program.
  const initialProgramId = typeof programId === "string" && UUID.test(programId) ? programId : undefined;
  return <EnrollmentsPage initialProgramId={initialProgramId} />;
}
