import type { Metadata } from "next";
import { MembershipDetailPage } from "@/features/memberships/components/membership-detail-page";

export const metadata: Metadata = {
  title: `Membership Details`,
};

export default async function Page({ params }: { params: Promise<{ membershipId: string }> }) {
  const { membershipId } = await params;
  return <MembershipDetailPage membershipId={membershipId} />;
}