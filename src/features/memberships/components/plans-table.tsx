"use client";

import { useMemo, useState } from "react";
import { CalendarDays, MoreHorizontal, Pencil, Power, Search } from "lucide-react";
import { Card } from "@/components/ui/card";
import { SelectField } from "@/components/shared/select-field";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { durationLabel, memberCountByPlan, monthlyEquivalentInr, planBand, type PlanBadge } from "@/features/memberships/plan-insights";
import type { MembershipListRow, MembershipPlan } from "@/features/memberships/types";
import { cn } from "@/lib/utils";

type Sort = "latest" | "oldest" | "name" | "price";

const SORTS: { value: Sort; label: string }[] = [
  { value: "latest", label: "Latest First" },
  { value: "oldest", label: "Oldest First" },
  { value: "name", label: "Name (A–Z)" },
  { value: "price", label: "Price: High to Low" },
];

const STATUSES = [
  { value: "", label: "All Status" },
  { value: "active", label: "Active" },
  { value: "inactive", label: "Inactive" },
];

const BAND_ICON: Record<string, string> = {
  Monthly: "bg-success/15 text-success",
  "3 Months": "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  "6 Months": "bg-warning/20 text-warning",
  "1 Year": "bg-purple-500/15 text-purple-600 dark:text-purple-400",
  Others: "bg-muted text-muted-foreground",
};

const CONTROL =
  "h-9 rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30 focus-visible:border-foreground/40";

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}
function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

/** "All Membership Plans": every plan with its roster size, status and date created. */
export function PlansTable({
  plans,
  rows,
  badges,
  className,
  onEdit,
  onToggleActive,
}: {
  plans: MembershipPlan[];
  rows: MembershipListRow[];
  badges: Map<string, PlanBadge>;
  /** Surface overrides — the Plans page passes its borderless glass treatment. */
  className?: string;
  onEdit: (plan: MembershipPlan) => void;
  onToggleActive: (plan: MembershipPlan) => void;
}) {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [sort, setSort] = useState<Sort>("latest");

  const counts = useMemo(() => memberCountByPlan(rows), [rows]);

  const visible = useMemo(() => {
    const list = plans.filter((p) => {
      if (status === "active" && !p.isActive) return false;
      if (status === "inactive" && p.isActive) return false;
      return p.name.toLowerCase().includes(search.trim().toLowerCase());
    });
    return [...list].sort((a, b) => {
      if (sort === "name") return a.name.localeCompare(b.name);
      if (sort === "price") return b.priceInr - a.priceInr;
      if (sort === "oldest") return a.createdAt.localeCompare(b.createdAt);
      return b.createdAt.localeCompare(a.createdAt);
    });
  }, [plans, search, status, sort]);

  return (
    <Card className={cn("stat-enter overflow-hidden rounded-xl p-0", className)} style={{ "--stat-delay": "420ms" } as React.CSSProperties}>
      <div className="flex flex-wrap items-center justify-between gap-3 p-4">
        <h3 className="text-base font-bold text-black dark:text-foreground">All Membership Plans ({plans.length})</h3>

        <div className="flex flex-wrap items-center gap-2">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <input
              type="text"
              aria-label="Search plans"
              placeholder="Search plans..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className={cn(CONTROL, "w-48 pl-9")}
            />
          </div>
          <SelectField
            wrapperClassName="w-[140px]"
            ariaLabel="Status"
            value={status}
            onValueChange={setStatus}
            options={STATUSES}
            className={CONTROL}
          />
          <SelectField
            wrapperClassName="w-[170px]"
            ariaLabel="Sort plans"
            value={sort}
            onValueChange={(v) => setSort(v as Sort)}
            options={SORTS}
            className={CONTROL}
          />
        </div>
      </div>

      <div className="overflow-x-auto border-t border-border">
        <table className="w-full text-sm">
          <thead className="bg-muted/40 text-left text-xs text-muted-foreground">
            <tr>
              <th className="px-4 py-3 font-medium">Plan Name</th>
              <th className="px-4 py-3 font-medium">Duration</th>
              <th className="px-4 py-3 font-medium">Price</th>
              <th className="px-4 py-3 font-medium">Members</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Created On</th>
              <th className="px-4 py-3 text-center font-medium">Actions</th>
            </tr>
          </thead>
          <tbody>
            {visible.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-12 text-center text-sm text-muted-foreground">
                  {plans.length === 0 ? "No plans yet. Create your first one." : "No plans match these filters."}
                </td>
              </tr>
            ) : (
              visible.map((p) => {
                const band = planBand(p.durationDays);
                const perMonth = monthlyEquivalentInr(p.priceInr, p.durationDays);
                const badge = badges.get(p.id);
                return (
                  <tr key={p.id} className="border-b border-border/60 transition-colors last:border-b-0 hover:bg-accent/40">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2.5">
                        <span className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-lg", BAND_ICON[band])}>
                          <CalendarDays className="h-4 w-4" aria-hidden />
                        </span>
                        <span className="font-medium text-foreground">{p.name}</span>
                        {badge && (
                          <span className="whitespace-nowrap rounded-full bg-success/15 px-2 py-0.5 text-[11px] font-semibold text-success">
                            {badge}
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{durationLabel(p.durationDays)}</td>
                    <td className="whitespace-nowrap px-4 py-3">
                      <span className="font-medium tabular-nums text-foreground">{inr(p.priceInr)}</span>
                      <span className="text-xs text-muted-foreground">
                        {band === "Monthly" ? " / month" : ` (${inr(perMonth)} / month)`}
                      </span>
                    </td>
                    <td className="px-4 py-3 tabular-nums text-foreground">{counts.get(p.id) ?? 0}</td>
                    <td className="px-4 py-3">
                      <span
                        className={cn(
                          "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-medium",
                          p.isActive ? "bg-success/15 text-success" : "bg-destructive/15 text-destructive",
                        )}
                      >
                        <span className="h-1.5 w-1.5 rounded-full bg-current" aria-hidden />
                        {p.isActive ? "Active" : "Inactive"}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{fmtDate(p.createdAt)}</td>
                    <td className="px-4 py-3">
                      <div className="flex justify-center">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <button
                              type="button"
                              aria-label={`Actions for ${p.name}`}
                              className="flex h-8 w-8 items-center justify-center rounded-lg border border-input text-muted-foreground outline-none transition-colors hover:bg-accent hover:text-foreground"
                            >
                              <MoreHorizontal className="h-4 w-4" />
                            </button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end" className="w-44">
                            <DropdownMenuItem onClick={() => onEdit(p)}>
                              <Pencil className="mr-2 h-4 w-4" />
                              Manage plans
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => onToggleActive(p)}>
                              <Power className="mr-2 h-4 w-4" />
                              {p.isActive ? "Deactivate" : "Activate"}
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
    </Card>
  );
}
