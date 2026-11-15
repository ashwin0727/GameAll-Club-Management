import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile, hasDashboardAccess } from "@/features/auth/api/auth.api";
import { SessionDetailPage } from "@/features/membership-sessions/components/session-detail-page";

export const metadata: Metadata = {
  title: `Membership Session Details`,
};

export default async function Page({ params }: { params: Promise<{ batchId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || !(await hasDashboardAccess(profile))) {
    redirect("/dashboard");
  }
  const { batchId } = await params;
  return <SessionDetailPage batchId={batchId} />;
}