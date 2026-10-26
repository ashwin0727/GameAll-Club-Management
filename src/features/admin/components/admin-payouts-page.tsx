"use client";

import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorNote, PageTitle } from "@/features/admin/components/admin-shell";
import { formatDate, placeLabel } from "@/features/admin/format";
import { usePayoutFacilities } from "@/features/admin/hooks";

/** Payout page: every facility, with how many of its bank / UPI details still need a check. */
export function AdminPayoutsPage() {
  const { data, isLoading, error } = usePayoutFacilities();

  return (
    <div>
      <PageTitle title="Payouts" subtitle="Check the bank account or UPI ID each facility wants its money sent to. Verified details show a Verified badge on the owner's profile." />
      {error ? (
        <ErrorNote error={error} />
      ) : isLoading ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : !data?.length ? (
        <p className="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">No facility has registered yet.</p>
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-xl border border-border bg-card">
          {data.map((f) => (
            <li key={f.id}>
              <Link href={`/admin/payouts/${f.id}`} className="flex items-center gap-4 px-4 py-4 transition-colors hover:bg-secondary/60 sm:px-5">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-semibold">{f.name}</p>
                  <p className="mt-0.5 truncate text-sm text-muted-foreground">
                    {f.ownerName ?? "—"} · {f.ownerEmail ?? "—"} · {placeLabel(f.city)}
                  </p>
                  {f.updatedAt && <p className="mt-0.5 text-xs text-muted-foreground">Last updated {formatDate(f.updatedAt)}</p>}
                </div>
                <div className="flex shrink-0 flex-wrap justify-end gap-1.5 text-xs font-semibold">
                  {f.total === 0 && <span className="rounded-full bg-muted px-2.5 py-0.5 text-muted-foreground">Nothing added</span>}
                  {f.pending > 0 && <span className="rounded-full bg-warning/15 px-2.5 py-0.5 text-warning">{f.pending} to verify</span>}
                  {f.verified > 0 && <span className="rounded-full bg-primary/10 px-2.5 py-0.5 text-primary">{f.verified} verified</span>}
                  {f.rejected > 0 && <span className="rounded-full bg-destructive/10 px-2.5 py-0.5 text-destructive">{f.rejected} rejected</span>}
                </div>
                <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
