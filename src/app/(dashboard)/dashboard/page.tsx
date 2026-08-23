import type { Metadata } from "next";
import { OwnerDashboard } from "@/features/dashboard/components/owner-dashboard";
import { getCurrentAuthUser } from "@/features/auth/api/auth.api";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Dashboard — ${PRODUCT_NAME}`,
};

export default async function DashboardPage() {
  const user = await getCurrentAuthUser();
  const firstName = user?.name?.split(" ")[0] ?? null;

  return <OwnerDashboard ownerFirstName={firstName} />;
}