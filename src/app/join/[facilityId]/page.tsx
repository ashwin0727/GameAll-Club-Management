import type { Metadata } from "next";
import { JoinMembershipForm } from "@/features/memberships/components/join-membership-form";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Join a membership — ${APP_NAME}`,
};

export default async function JoinPage({ params }: { params: Promise<{ facilityId: string }> }) {
  const { facilityId } = await params;

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4 py-10">
      <div className="rounded-xl border border-border bg-card p-6 shadow-sm">
        <JoinMembershipForm facilityId={facilityId} />
      </div>
      <p className="mt-4 text-center text-xs text-muted-foreground">Powered by {APP_NAME}</p>
    </main>
  );
}