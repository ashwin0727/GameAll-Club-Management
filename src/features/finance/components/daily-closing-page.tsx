"use client";

import { useCallback, useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { formatCurrency, fromMinorUnits, toMinorUnits } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import { ServiceError } from "@/services/shared/service-error";
import type { DailyClosingRow, DailyClosingSummary } from "@/features/finance/types";

function todayISO(): string {
  const d = new Date();
  return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, "0")}-${`${d.getDate()}`.padStart(2, "0")}`;
}

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

function statusTone(s: DailyClosingSummary["status"]): "success" | "warning" | "secondary" {
  if (s === "CLOSED") return "success";
  if (s === "OPEN" || s === "REOPENED") return "warning";
  return "secondary";
}

export function DailyClosingPage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [facilityName, setFacilityName] = useState("");
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [date, setDate] = useState(todayISO);

  const [summary, setSummary] = useState<DailyClosingSummary | null>(null);
  const [history, setHistory] = useState<DailyClosingRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [openingCash, setOpeningCash] = useState("");
  const [actualCash, setActualCash] = useState("");
  const [reason, setReason] = useState("");
  const [reopen, setReopen] = useState(false);
  const [reopenReason, setReopenReason] = useState("");

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then((facility) => {
        if (cancelled) return;
        if (!facility) return setLoadState("none");
        setFacilityId(facility.id);
        setFacilityName(facility.name);
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const finance = getFinanceService();
    const [s, h] = await Promise.all([
      finance.getDailyClosingSummary(facilityId, date),
      finance.listDailyClosings({ facilityId, dateRange: { preset: "THIS_MONTH" }, limit: 60 }),
    ]);
    setSummary(s);
    setHistory(h.closings);
    setActualCash(s.actualCashMinor != null ? String(fromMinorUnits(s.actualCashMinor, "INR")) : "");
    setReason(s.varianceReason ?? "");
  }, [facilityId, date]);

  useEffect(() => {
    let cancelled = false;
    setSummary(null);
    load().catch((err) => {
      if (cancelled) return;
      setError(err instanceof ServiceError ? err.message : "Unable to load the daily closing.");
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  async function run(action: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await action();
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Something went wrong. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load the daily closing.</p>;

  const s = summary;
  const expectedMinor = s?.expectedCashMinor ?? 0;
  const previewVariance = actualCash ? toMinorUnits(actualCash, "INR") - expectedMinor : null;
  const notStarted = s?.status === "NOT_STARTED";
  const closed = s?.status === "CLOSED";

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Daily Closing</h1>
          <p className="text-sm text-muted-foreground">
            Reconcile the day&apos;s collections and cash position{facilityName ? ` at ${facilityName}` : ""}.
          </p>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="dc-date" className="text-xs text-muted-foreground">
            Business date
          </Label>
          <Input
            id="dc-date"
            type="date"
            value={date}
            max={todayISO()}
            onChange={(e) => setDate(e.target.value)}
            className="w-[170px]"
          />
        </div>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      {s === null ? (
        <Skeleton className="h-72 w-full rounded-xl" />
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card className="space-y-3 p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Today&apos;s collections</h2>
              <span className="text-xs text-muted-foreground">{s.paymentCount} payments</span>
            </div>
            <dl className="space-y-1.5 text-sm">
              <Row label="Cash" value={s.cashCollectedMinor} />
              <Row label="UPI" value={s.upiCollectedMinor} />
              <Row label="Card" value={s.cardCollectedMinor} />
              <Row label="Online" value={s.onlineCollectedMinor} />
              <Row label="Bank transfer" value={s.bankTransferCollectedMinor} />
              <Row label="Other" value={s.otherCollectedMinor} />
              <div className="flex justify-between border-t border-border pt-1.5 font-semibold">
                <dt>Total collected</dt>
                <dd className="tabular-nums">{formatCurrency(s.totalCollectedMinor, "INR")}</dd>
              </div>
            </dl>

            <h2 className="pt-2 text-sm font-semibold">Today&apos;s expenses</h2>
            <dl className="space-y-1.5 text-sm">
              <Row label="Cash expenses" value={s.cashExpenseMinor} />
              <Row label="Other expenses" value={s.otherExpenseMinor} />
              <div className="flex justify-between border-t border-border pt-1.5 font-semibold">
                <dt>Total expenses</dt>
                <dd className="tabular-nums">{formatCurrency(s.totalExpenseMinor, "INR")}</dd>
              </div>
            </dl>
            {s.pendingPaymentCount > 0 && (
              <p className="text-xs text-muted-foreground">
                {s.pendingPaymentCount} booking(s) on this date are still unpaid — collect them before closing.
              </p>
            )}
          </Card>

          <Card className="space-y-3 p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Cash reconciliation</h2>
              <Badge variant={statusTone(s.status)}>{s.status.replace("_", " ")}</Badge>
            </div>

            {notStarted ? (
              <div className="space-y-3">
                <p className="text-sm text-muted-foreground">
                  The day for {fmtDate(s.closingDate)} has not been opened yet.
                </p>
                <div className="space-y-1.5">
                  <Label htmlFor="dc-opening" className="text-xs font-medium">
                    Opening cash float (₹)
                  </Label>
                  <Input
                    id="dc-opening"
                    inputMode="decimal"
                    value={openingCash}
                    onChange={(e) => setOpeningCash(e.target.value)}
                    placeholder={String(fromMinorUnits(s.openingCashMinor, "INR"))}
                  />
                </div>
                <Button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    run(() =>
                      getFinanceService().openDailyClosing(
                        facilityId!,
                        s.closingDate,
                        openingCash ? toMinorUnits(openingCash, "INR") : null,
                      ),
                    )
                  }
                >
                  Open day
                </Button>
              </div>
            ) : (
              <>
                <dl className="space-y-1.5 text-sm">
                  <Row label="Opening cash" value={s.openingCashMinor} />
                  <Row label="Cash collections" value={s.cashCollectedMinor} />
                  <Row label="Cash expenses" value={-s.cashExpenseMinor} />
                  <div className="flex justify-between border-t border-border pt-1.5 font-semibold">
                    <dt>Expected cash</dt>
                    <dd className="tabular-nums">{formatCurrency(s.expectedCashMinor, "INR")}</dd>
                  </div>
                </dl>

                <div className="space-y-1.5">
                  <Label htmlFor="dc-actual" className="text-xs font-medium">
                    Actual cash counted (₹)
                  </Label>
                  <Input
                    id="dc-actual"
                    inputMode="decimal"
                    value={actualCash}
                    disabled={closed}
                    onChange={(e) => setActualCash(e.target.value)}
                  />
                </div>

                {(previewVariance ?? s.varianceMinor) != null && (
                  <div className="flex justify-between text-sm">
                    <span className="text-muted-foreground">Variance</span>
                    <span
                      className={cn(
                        "font-semibold tabular-nums",
                        (previewVariance ?? s.varianceMinor ?? 0) < 0 && "text-destructive",
                        (previewVariance ?? s.varianceMinor ?? 0) > 0 && "text-warning",
                      )}
                    >
                      {formatCurrency(previewVariance ?? s.varianceMinor ?? 0, "INR")}
                    </span>
                  </div>
                )}

                {!closed && previewVariance != null && previewVariance !== 0 && (
                  <div className="space-y-1.5">
                    <Label htmlFor="dc-reason" className="text-xs font-medium">
                      Variance reason
                    </Label>
                    <Textarea
                      id="dc-reason"
                      rows={2}
                      value={reason}
                      onChange={(e) => setReason(e.target.value)}
                      placeholder="e.g. cash shortage, expense not recorded…"
                    />
                  </div>
                )}

                {closed ? (
                  <div className="space-y-2">
                    {s.varianceReason && (
                      <p className="text-xs text-muted-foreground">Reason: {s.varianceReason}</p>
                    )}
                    <p className="text-xs text-muted-foreground">Closed {s.closedAt ? fmtDate(s.closedAt) : ""}.</p>
                    <Button type="button" variant="outline" size="sm" onClick={() => setReopen(true)}>
                      Reopen day
                    </Button>
                  </div>
                ) : (
                  <Button
                    type="button"
                    disabled={busy || !actualCash}
                    onClick={() =>
                      run(() =>
                        getFinanceService().closeDailyClosing(
                          s.closingId!,
                          toMinorUnits(actualCash, "INR"),
                          reason.trim() || null,
                        ),
                      )
                    }
                  >
                    Complete closing
                  </Button>
                )}
              </>
            )}
          </Card>
        </div>
      )}

      <Card className="p-0">
        <div className="border-b border-border p-3">
          <h2 className="text-sm font-semibold">Recent closings</h2>
        </div>
        {history === null ? (
          <div className="space-y-2 p-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-10 w-full rounded-lg" />
            ))}
          </div>
        ) : history.length === 0 ? (
          <p className="p-6 text-center text-sm text-muted-foreground">No closings recorded this month.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-xs text-muted-foreground">
                  <th className="px-4 py-2.5 font-medium">Date</th>
                  <th className="px-4 py-2.5 text-right font-medium">Collected</th>
                  <th className="px-4 py-2.5 text-right font-medium">Expected</th>
                  <th className="px-4 py-2.5 text-right font-medium">Actual</th>
                  <th className="px-4 py-2.5 text-right font-medium">Variance</th>
                  <th className="px-4 py-2.5 font-medium">Status</th>
                  <th className="px-4 py-2.5 font-medium">Closed by</th>
                </tr>
              </thead>
              <tbody>
                {history.map((h) => (
                  <tr key={h.id} className="border-b border-border last:border-0">
                    <td className="whitespace-nowrap px-4 py-2.5">
                      <button className="font-medium hover:underline" onClick={() => setDate(h.closingDate.slice(0, 10))}>
                        {fmtDate(h.closingDate)}
                      </button>
                    </td>
                    <td className="px-4 py-2.5 text-right tabular-nums text-muted-foreground">
                      {h.totalCollectedMinor != null ? formatCurrency(h.totalCollectedMinor, "INR") : "—"}
                    </td>
                    <td className="px-4 py-2.5 text-right tabular-nums text-muted-foreground">
                      {h.expectedCashMinor != null ? formatCurrency(h.expectedCashMinor, "INR") : "—"}
                    </td>
                    <td className="px-4 py-2.5 text-right tabular-nums">
                      {h.actualCashMinor != null ? formatCurrency(h.actualCashMinor, "INR") : "—"}
                    </td>
                    <td
                      className={cn(
                        "px-4 py-2.5 text-right tabular-nums",
                        (h.varianceMinor ?? 0) < 0 && "text-destructive",
                        (h.varianceMinor ?? 0) > 0 && "text-warning",
                      )}
                    >
                      {h.varianceMinor != null ? formatCurrency(h.varianceMinor, "INR") : "—"}
                    </td>
                    <td className="px-4 py-2.5">
                      <Badge variant={h.status === "CLOSED" ? "success" : "warning"}>{h.status}</Badge>
                    </td>
                    <td className="px-4 py-2.5 text-muted-foreground">{h.closedByName ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Dialog open={reopen} onOpenChange={setReopen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Reopen this day</DialogTitle>
            <DialogDescription>
              Reopening is audited. Enter why the closed day needs to change.
            </DialogDescription>
          </DialogHeader>
          <Textarea rows={3} value={reopenReason} onChange={(e) => setReopenReason(e.target.value)} placeholder="Reason" />
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setReopen(false)} disabled={busy}>
              Cancel
            </Button>
            <Button
              type="button"
              disabled={busy || !reopenReason.trim()}
              onClick={() =>
                run(async () => {
                  await getFinanceService().reopenDailyClosing(s!.closingId!, reopenReason.trim());
                  setReopen(false);
                  setReopenReason("");
                })
              }
            >
              Reopen
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Row({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex justify-between">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="tabular-nums">{formatCurrency(value, "INR")}</dd>
    </div>
  );
}
