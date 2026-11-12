"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorNote, PageTitle } from "@/features/admin/components/admin-shell";
import { formatDateTime, placeLabel } from "@/features/admin/format";
import { useSetupReviews } from "@/features/admin/hooks";
import type { SetupReviewStatus } from "@/features/admin/service";
import { cn } from "@/lib/utils";

const TABS: { value: SetupReviewStatus | null; label: string }[] = [
  { value: "PENDING", label: "Waiting for review" },
  { value: "REJECTED", label: "Sent back" },
  { value: "APPROVED", label: "Approved" },
  { value: null, label: "All" },
];

export const REVIEW_BADGE: Record<SetupReviewStatus, { label: string; className: string }> = {
  NOT_SUBMITTED: { label: "Not submitted", className: "bg-muted text-muted-foreground" },
  PENDING: { label: "Waiting for review", className: "bg-warning/15 text-warning" },
  APPROVED: { label: "Approved", className: "bg-primary/10 text-primary" },
  REJECTED: { label: "Sent back", className: "bg-destructive/10 text-destructive" },
};

/**
 * Approvals: every facility that has finished setup, newest waiting first. A facility's people cannot open their dashboard until it
 * is approved here, so this queue is the gate.
 */
export function AdminReviewsPage() {
  const [tab, setTab] = useState<SetupReviewStatus | null>("PENDING");
  const { data, isLoading, error } = useSetupReviews(tab);

  return (
    <div>
      <PageTitle
        title="Approvals"
        subtitle="Review everything an owner entered, from Facility Information to Payout. They can use their dashboard only after you approve."
      />
      <div role="tablist" aria-label="Filter by status" className="mb-4 flex flex-wrap gap-1.5">
        {TABS.map((t) => (
          <button
            key={t.label}
            type="button"
            role="tab"
            aria-selected={tab === t.value}
            onClick={() => setTab(t.value)}
            className={cn(
              "rounded-lg px-3.5 py-1.5 text-sm font-medium transition-colors",
              tab === t.value ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground hover:text-foreground",
            )}
          >
            {t.label}
          </button>
        ))}
      </div>
      {error ? (
        <ErrorNote error={error} />
      ) : isLoading ? (
        <Skeleton className="h-64 w-full rounded-xl" />
      ) : !data?.length ? (
        <p className="rounded-xl border border-border bg-card p-10 text-center text-sm text-muted-foreground">Nothing here.</p>
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-xl border border-border bg-card">
          {data.map((r) => (
            <li key={r.id}>
              <Link href={`/admin/reviews/${r.id}`} className="flex items-center gap-4 px-4 py-4 transition-colors hover:bg-secondary/60 sm:px-5">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-semibold">{r.name}</p>
                  <p className="mt-0.5 truncate text-sm text-muted-foreground">
                    {r.ownerName ?? "—"} · {r.ownerEmail ?? "—"} · {placeLabel(r.city, r.state)}
                  </p>
                  <p className="mt-0.5 text-xs text-muted-foreground">
                    {r.status === "PENDING" ? `Submitted ${formatDateTime(r.submittedAt)}` : `Reviewed ${formatDateTime(r.reviewedAt)}`}
                  </p>
                </div>
                <div className="flex shrink-0 flex-wrap justify-end gap-1.5 text-xs font-semibold">
                  <span className={cn("rounded-full px-2.5 py-0.5", r.payoutVerified > 0 ? "bg-primary/10 text-primary" : "bg-warning/15 text-warning")}>
                    Payout {r.payoutVerified}/{r.payoutTotal} verified
                  </span>
                  <span className={cn("rounded-full px-2.5 py-0.5", REVIEW_BADGE[r.status].className)}>{REVIEW_BADGE[r.status].label}</span>
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
