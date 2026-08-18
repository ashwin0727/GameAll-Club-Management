import type { Metadata } from "next";
import { CheckCircle2 } from "lucide-react";
import { StatCards } from "@/features/dashboard/components/stat-cards";
import { getCurrentAuthUser } from "@/features/auth/api/auth.api";
import { createClient } from "@/lib/supabase/server";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Dashboard — ${PRODUCT_NAME}`,
};

export default async function DashboardPage() {
  const supabase = await createClient();
  const user = await getCurrentAuthUser(supabase);
  const firstName = user?.name?.split(" ")[0];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">
          {firstName ? `Welcome back, ${firstName}` : "Dashboard"}
        </h1>
        <p className="text-sm text-muted-foreground">
          Overview of memberships, bookings, and revenue.
        </p>
      </div>

      {/* Confirms the signed-in identity while facility setup is still to come.
          Replaced by the facility summary in the next phase. */}
      <section className="rounded-xl border border-border bg-card p-5">
        <div className="flex items-start gap-3">
          <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-success" aria-hidden="true" />
          <div className="min-w-0 space-y-1">
            <p className="text-sm font-medium">Authentication flow completed.</p>
            <p className="break-words text-sm text-muted-foreground">
              Signed in as <span className="text-foreground">{user?.name}</span> ·{" "}
              <span className="text-foreground">{user?.email}</span>
            </p>
            <p className="text-sm text-muted-foreground">
              Facility setup — sports, courts and pricing — comes next.
            </p>
          </div>
        </div>
      </section>

      <StatCards />
    </div>
  );
}