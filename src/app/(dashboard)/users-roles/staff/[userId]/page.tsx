import type { Metadata } from "next";
import { StaffDetailsPage } from "@/features/staff/components/staff-details-page";

export const metadata: Metadata = { title: `Staff Details` };

export default async function Page({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;
  return <StaffDetailsPage userId={userId} />;
}
