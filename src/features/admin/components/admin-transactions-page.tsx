"use client";

import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorNote, PageTitle } from "@/features/admin/components/admin-shell";
import { formatDate, inr, placeLabel } from "@/features/admin/format";
import { useTransactionFacilities } from "@/features/admin/hooks";

/** Transactions page: every facility, with what is waiting to be settled and what already has been. */
export function AdminTransactionsPage() {
  const { data, isLoading, error } = useTransactionFacilities();

  return (
    <div>
      <PageTitle
        title="Transactions"
        subtitle="Online payments only — Razorpay, UPI, UPI AutoPay, cards and bank transfers. Cash and other offline entries are not listed."
      />
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
              <Link href={`/admin/transactions/${f.id}`} className="flex items-center gap-4 px-4 py-4 transition-colors hover:bg-secondary/60 sm:px-5">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-semibold">{f.name}</p>
                  <p className="mt-0.5 text-sm text-muted-foreground">
                    {placeLabel(f.city)}
                    {f.lastAt ? ` · Last payment ${formatDate(f.lastAt)}` : " · No online payments yet"}
                  </p>
                </div>
                <dl className="grid shrink-0 grid-cols-2 gap-6 text-right text-sm">
                  <div>
                    <dd className={f.recentInr > 0 ? "font-semibold text-warning" : "font-semibold"}>{inr(f.recentInr)}</dd>
                    <dt className="text-xs text-muted-foreground">{f.recentCount} to settle</dt>
                  </div>
                  <div>
                    <dd className="font-semibold">{inr(f.settledInr)}</dd>
                    <dt className="text-xs text-muted-foreground">{f.settledCount} settled</dt>
                  </div>
                </dl>
                <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
