import type { Metadata } from "next";
import { MembershipDetailPage } from "@/features/memberships/components/membership-detail-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Membership Details — ${APP_NAME}`,
};

export default async function Page({ params }: { params: Promise<{ membershipId: string }> }) {
  const { membershipId } = await params;
  return <MembershipDetailPage membershipId={membershipId} />;
}