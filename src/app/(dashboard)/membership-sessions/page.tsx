import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/features/auth/api/auth.api";
import { MembershipAvailabilityView } from "@/features/membership-sessions/components/membership-availability-view";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Membership Sessions — ${APP_NAME}`,
};

export default async function MembershipSessionsPage() {
  const profile = await getCurrentProfile();

  if (!profile || (profile.role !== "admin" && profile.role !== "staff")) {
    redirect("/dashboard");
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Membership Sessions</h1>
        <p className="text-sm text-muted-foreground">
          Manage recurring membership batches and release unused capacity for guest booking.
        </p>
      </div>
      <MembershipAvailabilityView />
    </div>
  );
}