import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { SessionDetailPage } from "@/features/membership-sessions/components/session-detail-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Membership Session Details — ${APP_NAME}`,
};

export default async function Page({ params }: { params: Promise<{ batchId: string }> }) {
  const profile = await getCurrentProfile();
  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }
  const { batchId } = await params;
  return <SessionDetailPage batchId={batchId} />;
}