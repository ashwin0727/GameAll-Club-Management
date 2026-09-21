"use client";

import { ArrowDown, ArrowUp, Check, Copy, MoreVertical, UserRound } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { CustomerAvatar } from "@/features/bookings/components/customer-avatar";
import { displayPhone, formatBookingDate } from "@/features/bookings/guest-booking-table";
import type { GuestProfile, PotentialSortDir } from "@/features/bookings/potential-members";
import { formatCurrency } from "@/features/pricing/money";
import { cn } from "@/lib/utils";

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
      className="h-4 w-4 cursor-pointer rounded border-input accent-[#0B7A55]"
    />
  );
}

/**
 * The potential members table: a checkbox, the guest (initials and "Frequent / Returning
 * Guest"), their number, total bookings (click to sort), last booking, sport, total spent, an
 * Invite to Member button that copies the join link, and a ⋮ menu.
 */
export function PotentialMembersTable({
  rows,
  selected,
  onToggle,
  onTogglePage,
  sortDir,
  onSortBookings,
  sportIcon,
  sportName,
  copiedKey,
  onInvite,
  onViewProfile,
  onCopyPhone,
}: {
  /** The page of guests to show; undefined while loading. */
  rows: GuestProfile[] | undefined;
  selected: ReadonlySet<string>;
  onToggle: (key: string) => void;
  onTogglePage: (checked: boolean) => void;
  sortDir: PotentialSortDir;
  onSortBookings: () => void;
  sportIcon: string;
  sportName: string;
  /** The guest whose link was just copied (shows "Link copied"). */
  copiedKey: string | null;
  onInvite: (guest: GuestProfile) => void;
  onViewProfile: (guest: GuestProfile) => void;
  onCopyPhone: (guest: GuestProfile) => void;
}) {
  const pageAll = !!rows && rows.length > 0 && rows.every((g) => selected.has(g.key));
  const pageSome = !!rows && rows.some((g) => selected.has(g.key));
  const SortIcon = sortDir === "asc" ? ArrowUp : ArrowDown;

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="border-b border-border text-left text-xs text-muted-foreground">
          <tr>
            <th className="w-10 px-4 py-3">
              <Checkbox checked={pageAll} indeterminate={pageSome} onChange={onTogglePage} label="Select all guests on this page" />
            </th>
            <th className="px-4 py-3 font-medium">Guest</th>
            <th className="px-4 py-3 font-medium">Contact</th>
            <th className="px-4 py-3 text-center font-medium" aria-sort={sortDir === "asc" ? "ascending" : "descending"}>
              <button
                type="button"
                onClick={onSortBookings}
                className="mx-auto flex items-center gap-1 whitespace-nowrap text-foreground transition-colors hover:text-foreground"
              >
                Total Bookings
                <SortIcon className="h-3 w-3" aria-hidden />
              </button>
            </th>
            <th className="px-4 py-3 font-medium">Last Booking</th>
            <th className="px-4 py-3 font-medium">Preferred Sport</th>
            <th className="px-4 py-3 font-medium">Total Spent</th>
            <th className="px-4 py-3 text-center font-medium">Actions</th>
          </tr>
        </thead>
        <tbody>
          {rows === undefined ? (
            Array.from({ length: 6 }).map((_, i) => (
              <tr key={i} className="border-b border-border/60">
                <td colSpan={8} className="px-4 py-3">
                  <Skeleton className="h-10 w-full" />
                </td>
              </tr>
            ))
          ) : rows.length === 0 ? (
            <tr>
              <td colSpan={8} className="px-4 py-12 text-center text-sm text-muted-foreground">
                No guests match these filters.
              </td>
            </tr>
          ) : (
            rows.map((g) => {
              const isSelected = selected.has(g.key);
              return (
                <tr
                  key={g.key}
                  className={cn("border-b border-border/60 transition-colors last:border-b-0 hover:bg-accent/40", isSelected && "bg-primary/[0.05]")}
                >
                  <td className="px-4 py-3">
                    <Checkbox checked={isSelected} onChange={() => onToggle(g.key)} label={`Select ${g.name}`} />
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                      <CustomerAvatar name={g.name} className="h-10 w-10 text-sm" />
                      <div className="min-w-0">
                        <p className="max-w-[10rem] truncate font-medium text-foreground">{g.name}</p>
                        <p className="text-xs text-muted-foreground">{g.label} Guest</p>
                      </div>
                    </div>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 tabular-nums text-foreground/80">{displayPhone(g.phone)}</td>
                  <td className="px-4 py-3 text-center font-medium tabular-nums">{g.bookings}</td>
                  <td className="whitespace-nowrap px-4 py-3 text-foreground/80">{formatBookingDate(g.lastBookingAt)}</td>
                  <td className="px-4 py-3">
                    <span className="flex items-center gap-2 whitespace-nowrap">
                      <span aria-hidden className="text-lg leading-none">
                        {sportIcon}
                      </span>
                      {sportName}
                    </span>
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 font-medium tabular-nums">{formatCurrency(g.totalSpentMinor, "INR")}</td>
                  <td className="px-4 py-3">
                    <div className="flex items-center justify-center gap-2">
                      <button
                        type="button"
                        onClick={() => onInvite(g)}
                        className="flex h-9 items-center gap-1.5 whitespace-nowrap rounded-[8px] border border-[#0B7A55] bg-card px-3 text-xs font-medium text-[#0B7A55] transition-colors hover:bg-[#0B7A55]/10 dark:border-primary dark:text-primary dark:hover:bg-primary/10"
                      >
                        {copiedKey === g.key ? (
                          <>
                            <Check className="h-3.5 w-3.5" aria-hidden />
                            Link copied
                          </>
                        ) : (
                          "Invite to Member"
                        )}
                      </button>
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <button
                            type="button"
                            aria-label={`More actions for ${g.name}`}
                            className="flex h-9 w-9 items-center justify-center rounded-[8px] text-muted-foreground outline-none transition-colors hover:bg-accent hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
                          >
                            <MoreVertical className="h-4 w-4" />
                          </button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end" className="w-52">
                          <DropdownMenuItem className="gap-2.5 py-2" onClick={() => onViewProfile(g)}>
                            <UserRound className="h-4 w-4" />
                            View guest profile
                          </DropdownMenuItem>
                          <DropdownMenuItem className="gap-2.5 py-2" onClick={() => onCopyPhone(g)}>
                            <Copy className="h-4 w-4" />
                            Copy phone number
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </div>
                  </td>
                </tr>
              );
            })
          )}
        </tbody>
      </table>
    </div>
  );
}
