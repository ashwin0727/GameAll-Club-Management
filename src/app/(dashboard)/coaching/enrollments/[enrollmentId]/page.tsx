import type { Metadata } from "next";
import { EnrollmentDetailsPage } from "@/features/coaching/components/enrollment-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Enrollment — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ enrollmentId: string }> }) {
  const { enrollmentId } = await params;
  return <EnrollmentDetailsPage enrollmentId={enrollmentId} />;
}
