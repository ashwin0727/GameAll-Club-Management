"use client";

import { useState } from "react";
import { Check, Undo2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { ErrorNote, PageTitle } from "@/features/admin/components/admin-shell";
import { formatDateTime, inr } from "@/features/admin/format";
import { PAGE_SIZE, useAdminFacility, useSettle, useTransactions, useUnsettle } from "@/features/admin/hooks";
import type { AdminTransaction, TransactionView } from "@/features/admin/service";
import { cn } from "@/lib/utils";

const TABS: { id: TransactionView; label: string }[] = [
  { id: "recent", label: "Recent transactions" },
  { id: "settled", label: "Settled transactions" },
];

/** One facility's online payments, split into Recent (not yet sent on) and Settled, with the Settled button. */
export function AdminTransactionDetailPage({ facilityId }: { facilityId: string }) {
  const [view, setView] = useState<TransactionView>("recent");
  const [offset, setOffset] = useState(0);
  const [confirm, setConfirm] = useState<{ ids: string[]; amount: number } | null>(null);

  const facility = useAdminFacility(facilityId);
  const tx = useTransactions(facilityId, view, offset);
  const settle = useSettle();
  const unsettle = useUnsettle();
  const rows = tx.data?.rows ?? [];
  const total = tx.data?.total ?? 0;
  const settlable = rows.filter((r) => r.status === "paid");

  function switchView(next: TransactionView) {
    setView(next);
    setOffset(0);
  }

  return (
    <div>
      <PageTitle
        back={{ href: "/admin/transactions", label: "All facilities" }}
        title={facility.data?.facility.name ?? "Transactions"}
        subtitle="Online payments only. Mark a payment Settled once the money has been sent to the facility."
      />

      <div role="tablist" aria-label="Transaction view" className="mb-4 inline-flex rounded-lg border border-border bg-muted/50 p-1 text-sm">
        {TABS.map((t) => (
          <button
            key={t.id}
            role="tab"
            aria-selected={view === t.id}
            onClick={() => switchView(t.id)}
            className={cn(
              "rounded-md px-4 py-1.5 font-medium transition-colors",
              view === t.id ? "bg-background text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground",
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {(tx.error || settle.error || unsettle.error) && (
        <div className="mb-4">
          <ErrorNote error={tx.error ?? settle.error ?? unsettle.error} />
        </div>
      )}

      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          {tx.isLoading ? "Loading…" : `${total} transaction${total === 1 ? "" : "s"} · ${inr(tx.data?.totalInr)}`}
        </p>
        {view === "recent" && settlable.length > 1 && (
          <Button
            size="sm"
            variant="outline"
            disabled={settle.isPending}
            onClick={() => setConfirm({ ids: settlable.map((r) => r.id), amount: settlable.reduce((s, r) => s + r.amountInr, 0) })}
          >
            Settle all {settlable.length} shown
          </Button>
        )}
      </div>

      <div className="overflow-hidden rounded-xl border border-border bg-card">
        {tx.isLoading ? (
          <Skeleton className="h-64 w-full rounded-none" />
        ) : rows.length === 0 ? (
          <p className="p-10 text-center text-sm text-muted-foreground">
            {view === "recent" ? "Nothing waiting to be settled." : "No payment has been marked as settled yet."}
          </p>
        ) : (
          <div className={cn("overflow-x-auto", tx.isFetching && "opacity-70")}>
            <table className="w-full min-w-[820px] text-sm">
              <thead className="border-b border-border bg-muted/40 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-4 py-3 font-medium">Date</th>
                  <th className="px-4 py-3 font-medium">For</th>
                  <th className="px-4 py-3 font-medium">Paid by</th>
                  <th className="px-4 py-3 font-medium">Method</th>
                  <th className="px-4 py-3 font-medium">Razorpay ID</th>
                  <th className="px-4 py-3 text-right font-medium">Amount</th>
                  <th className="px-4 py-3 text-right font-medium">{view === "recent" ? "" : "Settled"}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {rows.map((r) => (
                  <Row
                    key={r.id}
                    r={r}
                    view={view}
                    busy={settle.isPending || unsettle.isPending}
                    onSettle={() => setConfirm({ ids: [r.id], amount: r.amountInr })}
                    onUndo={() => unsettle.mutate(r.id)}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {total > PAGE_SIZE && (
        <div className="mt-4 flex items-center justify-between text-sm text-muted-foreground">
          <span>
            {offset + 1}–{Math.min(offset + PAGE_SIZE, total)} of {total}
          </span>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}>
              Previous
            </Button>
            <Button variant="outline" size="sm" disabled={offset + PAGE_SIZE >= total} onClick={() => setOffset(offset + PAGE_SIZE)}>
              Next
            </Button>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={confirm !== null}
        title={confirm && confirm.ids.length > 1 ? `Settle ${confirm.ids.length} payments?` : "Mark as settled?"}
        description={
          confirm ? (
            <>
              This records that <strong>{inr(confirm.amount)}</strong> has been sent to {facility.data?.facility.name ?? "the facility"}. You can undo it
              from the Settled tab.
            </>
          ) : null
        }
        confirmLabel="Settled"
        busyLabel="Saving…"
        busy={settle.isPending}
        onCancel={() => setConfirm(null)}
        onConfirm={() => confirm && settle.mutate({ ids: confirm.ids, note: null }, { onSuccess: () => setConfirm(null) })}
      />
    </div>
  );
}

function Row({
  r,
  view,
  busy,
  onSettle,
  onUndo,
}: {
  r: AdminTransaction;
  view: TransactionView;
  busy: boolean;
  onSettle: () => void;
  onUndo: () => void;
}) {
  return (
    <tr className="align-top">
      <td className="whitespace-nowrap px-4 py-3">{formatDateTime(r.at)}</td>
      <td className="px-4 py-3">
        <span className="rounded-full bg-secondary px-2 py-0.5 text-xs font-medium">{r.source}</span>
      </td>
      <td className="px-4 py-3">{r.payer ?? "—"}</td>
      <td className="px-4 py-3 text-muted-foreground">{r.method}</td>
      <td className="px-4 py-3 font-mono text-xs text-muted-foreground">
        <span className="select-all">{r.razorpayPaymentId}</span>
      </td>
      <td className="whitespace-nowrap px-4 py-3 text-right font-semibold">
        {inr(r.amountInr)}
        {r.status === "refunded" && <span className="ml-2 rounded-full bg-destructive/10 px-2 py-0.5 text-[11px] font-semibold text-destructive">Refunded</span>}
      </td>
      <td className="whitespace-nowrap px-4 py-3 text-right">
        {view === "recent" ? (
          r.status === "paid" ? (
            <Button size="sm" disabled={busy} onClick={onSettle}>
              <Check className="mr-1.5 h-4 w-4" aria-hidden /> Settled
            </Button>
          ) : (
            <span className="text-xs text-muted-foreground">Not payable</span>
          )
        ) : (
          <div className="flex items-center justify-end gap-3">
            <span className="text-xs text-muted-foreground">{formatDateTime(r.settledAt)}</span>
            <Button variant="ghost" size="sm" disabled={busy} onClick={onUndo} aria-label="Undo settled">
              <Undo2 className="h-4 w-4" aria-hidden />
            </Button>
          </div>
        )}
      </td>
    </tr>
  );
}
