"use client";

import { ArrowDown, ArrowUp, ChevronsUpDown } from "lucide-react";
import { EVENT_CHIP_STYLE, formatClock } from "@/features/bookings/components/booking-event-style";
import { CustomerAvatar } from "@/features/bookings/components/customer-avatar";
import { PaginationControls } from "@/features/bookings/components/pagination-controls";
import {
  courtText,
  maskPhone,
  TYPE_LABEL,
  type BookingRow,
  type ListKind,
  type SortDir,
  type SortKey,
} from "@/features/bookings/list-utils";
import { formatCurrency } from "@/features/pricing/money";
import { cn } from "@/lib/utils";

export const PAGE_SIZES = [12, 25, 50];

/** Memberships share the amber of membership sessions on the calendar; everything else matches its calendar colour. */
const KIND_STYLE: Record<ListKind, string> = {
  GUEST: EVENT_CHIP_STYLE.GUEST,
  MEMBERSHIP: EVENT_CHIP_STYLE.SESSION,
  COACHING: EVENT_CHIP_STYLE.COACHING,
};

const STATUS_BADGE: Record<BookingRow["status"], { label: string; cls: string; dot: string }> = {
  confirmed: { label: "Confirmed", cls: "bg-success/10 text-success", dot: "bg-success" },
  pending: { label: "Pending", cls: "bg-warning/10 text-warning", dot: "bg-warning" },
  completed: { label: "Completed", cls: "bg-blue-500/10 text-blue-600 dark:text-blue-400", dot: "bg-blue-500" },
  cancelled: { label: "Cancelled", cls: "bg-destructive/10 text-destructive", dot: "bg-destructive" },
};

const DATE_FMT = new Intl.DateTimeFormat("en-IN", { day: "2-digit", month: "short", year: "numeric" });

const COLUMNS: { key: SortKey; label: string }[] = [
  { key: "date", label: "Date & Time" },
  { key: "customer", label: "Customer" },
  { key: "court", label: "Court(s)" },
  { key: "type", label: "Type" },
  { key: "duration", label: "Duration" },
  { key: "amount", label: "Amount" },
  { key: "status", label: "Status" },
];

function Checkbox({
  checked,
  indeterminate,
  onChange,
  label,
}: {
  checked: boolean;
  indeterminate?: boolean;
  onChange: (checked: boolean) => void;
  label: string;
}) {
  return (
    <input
      type="checkbox"
      aria-label={label}
      checked={checked}
      ref={(el) => {
        if (el) el.indeterminate = Boolean(indeterminate) && !checked;
      }}
      onChange={(e) => onChange(e.target.checked)}
      onClick={(e) => e.stopPropagation()}
      className="h-4 w-4 cursor-pointer rounded border-input accent-[#0B7A55]"
    />
  );
}

/**
 * The bookings table: sortable columns, row hover, checkbox selection, status
 * badges, masked phone numbers and pagination. Presentational — the tab above
 * it owns the data, sort, selection and paging state.
 */
export function BookingTable({
  rows,
  total,
  sortKey,
  sortDir,
  onSort,
  selected,
  onToggle,
  onTogglePage,
  courtName,
  onOpen,
  renderActions,
  page,
  pages,
  perPage,
  onPage,
  onPerPage,
  emptyText,
}: {
  /** Just the current page. */
  rows: BookingRow[];
  total: number;
  sortKey: SortKey;
  sortDir: SortDir;
  onSort: (key: SortKey) => void;
  selected: Set<string>;
  onToggle: (id: string) => void;
  onTogglePage: (checked: boolean) => void;
  courtName: (courtId: string) => string;
  onOpen: (row: BookingRow) => void;
  /** The row's menu. */
  renderActions: (row: BookingRow) => React.ReactNode;
  page: number;
  pages: number;
  perPage: number;
  onPage: (page: number) => void;
  onPerPage: (perPage: number) => void;
  emptyText: string;
}) {
  const pageSelected = rows.length > 0 && rows.every((r) => selected.has(r.id));
  const pageSome = rows.some((r) => selected.has(r.id));
  const shownFrom = total === 0 ? 0 : (page - 1) * perPage + 1;
  const shownTo = Math.min(page * perPage, total);

  return (
    <div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[860px] text-left text-sm">
          <thead>
            <tr className="border-b border-border text-xs text-muted-foreground">
              <th className="w-10 px-3 py-3">
                <Checkbox checked={pageSelected} indeterminate={pageSome} onChange={onTogglePage} label="Select all on this page" />
              </th>
              {COLUMNS.map((c) => {
                const active = sortKey === c.key;
                const Icon = !active ? ChevronsUpDown : sortDir === "asc" ? ArrowUp : ArrowDown;
                return (
                  <th
                    key={c.key}
                    aria-sort={active ? (sortDir === "asc" ? "ascending" : "descending") : "none"}
                    className="px-3 py-3 font-medium"
                  >
                    <button
                      type="button"
                      onClick={() => onSort(c.key)}
                      className={cn("flex items-center gap-1 whitespace-nowrap hover:text-foreground", active && "text-foreground")}
                    >
                      {c.label}
                      <Icon className="h-3 w-3" aria-hidden />
                    </button>
                  </th>
                );
              })}
              <th className="px-3 py-3 text-right font-medium">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border/60">
            {rows.length === 0 ? (
              <tr>
                <td colSpan={9} className="px-3 py-14 text-center text-sm text-muted-foreground">
                  {emptyText}
                </td>
              </tr>
            ) : (
              rows.map((r) => {
                const status = STATUS_BADGE[r.status];
                const isSelected = selected.has(r.id);
                return (
                  <tr
                    key={r.id}
                    onClick={() => onOpen(r)}
                    className={cn("cursor-pointer transition-colors hover:bg-accent/50", isSelected && "bg-primary/[0.06]")}
                  >
                    <td className="px-3 py-3">
                      <Checkbox checked={isSelected} onChange={() => onToggle(r.id)} label={`Select booking ${r.reference}`} />
                    </td>
                    <td className="whitespace-nowrap px-3 py-3">
                      <p className="font-medium">{DATE_FMT.format(r.start)}</p>
                      <p className="max-w-[13rem] truncate text-xs tabular-nums text-muted-foreground" title={r.timeLabel ?? undefined}>
                        {r.timeLabel ?? `${formatClock(r.start)} - ${formatClock(r.end)}`}
                      </p>
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-2.5">
                        <CustomerAvatar name={r.customerName} className="h-8 w-8 text-[11px]" />
                        <span className="min-w-0">
                          <p className="max-w-[10rem] truncate font-medium">{r.customerName}</p>
                          <p className="text-xs tabular-nums text-muted-foreground">{maskPhone(r.customerPhone)}</p>
                        </span>
                      </div>
                    </td>
                    <td className="whitespace-nowrap px-3 py-3">{courtText(r, courtName)}</td>
                    <td className="px-3 py-3">
                      <span className={cn("rounded-md px-2 py-1 text-xs font-medium", KIND_STYLE[r.kind])}>{TYPE_LABEL[r.kind]}</span>
                    </td>
                    <td className="px-3 py-3">
                      <p className="whitespace-nowrap">{r.durationLabel}</p>
                      {r.durationSub && (
                        <p className="max-w-[11rem] truncate text-xs text-muted-foreground" title={r.durationSub}>
                          {r.durationSub}
                        </p>
                      )}
                    </td>
                    <td className="px-3 py-3">
                      <p className="whitespace-nowrap tabular-nums">
                        {r.amountMinor === null ? "—" : formatCurrency(r.amountMinor, r.currency)}
                      </p>
                      {r.amountSub && <p className="whitespace-nowrap text-xs text-muted-foreground">{r.amountSub}</p>}
                    </td>
                    <td className="px-3 py-3">
                      <span className={cn("inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium", status.cls)}>
                        <span className={cn("h-1.5 w-1.5 rounded-full", status.dot)} />
                        {r.statusLabel}
                      </span>
                    </td>
                    <td className="px-3 py-3 text-right" onClick={(e) => e.stopPropagation()}>
                      {renderActions(r)}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* Footer: count, pages, page size */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-3 py-3">
        <p className="text-xs text-muted-foreground">
          Showing {shownFrom}–{shownTo} of {total} booking{total === 1 ? "" : "s"}
        </p>
        <PaginationControls
          page={page}
          pages={pages}
          perPage={perPage}
          pageSizes={PAGE_SIZES}
          onPage={onPage}
          onPerPage={onPerPage}
        />
      </div>
    </div>
  );
}
