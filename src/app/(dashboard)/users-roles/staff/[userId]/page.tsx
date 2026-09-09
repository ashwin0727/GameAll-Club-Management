import type { Metadata } from "next";
import { StaffDetailsPage } from "@/features/staff/components/staff-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Staff Details — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;
  return <StaffDetailsPage userId={userId} />;
}
