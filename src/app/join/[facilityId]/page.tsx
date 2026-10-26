import type { Metadata } from "next";
import { JoinMembershipForm } from "@/features/memberships/components/join-membership-form";
import { APP_NAME } from "@/lib/constants";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: `Join a membership — ${APP_NAME}`,
};

/** Whether the club's plan lets players enrol in memberships themselves (Advanced). A failed check keeps the form open. */
async function acceptsMemberships(facilityId: string): Promise<boolean> {
  try {
    const supabase = await createClient();
    const { data, error } = await (supabase.rpc as unknown as (fn: string, args: object) => Promise<{ data: boolean | null; error: unknown }>).call(
      supabase,
      "public_facility_accepts_memberships",
      { p_facility_id: facilityId },
    );
    return error ? true : data !== false;
  } catch {
    return true;
  }
}

export default async function JoinPage({ params }: { params: Promise<{ facilityId: string }> }) {
  const { facilityId } = await params;
  const open = await acceptsMemberships(facilityId);

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4 py-10">
      <div className="rounded-xl border border-border bg-card p-6 shadow-sm">
        {open ? (
          <JoinMembershipForm facilityId={facilityId} />
        ) : (
          <div className="space-y-2 text-center">
            <h1 className="text-lg font-semibold">Memberships aren&apos;t open online yet</h1>
            <p className="text-sm text-muted-foreground">
              This club isn&apos;t taking membership sign-ups through the app. You can still book a guest slot, or ask the club to set up your membership.
            </p>
          </div>
        )}
      </div>
      <p className="mt-4 text-center text-xs text-muted-foreground">Powered by {APP_NAME}</p>
    </main>
  );
}
