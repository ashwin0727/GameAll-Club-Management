"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronRight, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorNote, PageTitle, Stat } from "@/features/admin/components/admin-shell";
import { formatDate, humanize, inr, placeLabel } from "@/features/admin/format";
import { PAGE_SIZE, useAdminFacilities, useAdminOverview } from "@/features/admin/hooks";
import { cn } from "@/lib/utils";

/** Admin home: every facility that has registered, with the headline numbers for each. */
export function AdminHomePage() {
  const [input, setInput] = useState("");
  const [search, setSearch] = useState("");
  const [offset, setOffset] = useState(0);
  const overview = useAdminOverview();
  const list = useAdminFacilities(search, offset);
  const total = list.data?.total ?? 0;

  return (
    <div>
      <PageTitle title="Facilities" subtitle="Every facility registered on GameAll, with how it is set up and how it is doing." />

      {overview.error ? (
        <ErrorNote error={overview.error} />
      ) : (
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          {overview.isLoading || !overview.data ? (
            Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)
          ) : (
            <>
              <Stat label="Facilities" value={overview.data.facilities} hint={`${overview.data.onboarded} set up · ${overview.data.inProgress} in progress`} />
              <Stat label="Courts" value={overview.data.courts} hint={`${overview.data.sports} sports offered`} />
              <Stat label="Active memberships" value={overview.data.activeMemberships} hint={`${overview.data.activeStudents} coaching students`} />
              <Stat label="Waiting to be settled" value={inr(overview.data.unsettledInr)} hint={`${overview.data.payoutsPending} payout details to verify`} />
            </>
          )}
        </div>
      )}

      <form
        className="mt-8 flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          setOffset(0);
          setSearch(input.trim());
        }}
      >
        <div className="relative max-w-md flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input value={input} onChange={(e) => setInput(e.target.value)} placeholder="Search facility, owner, city or phone" className="pl-9" aria-label="Search facilities" />
        </div>
        <Button type="submit" variant="outline">
          Search
        </Button>
      </form>

      <div className="mt-4 overflow-hidden rounded-xl border border-border bg-card">
        {list.error ? (
          <div className="p-4">
            <ErrorNote error={list.error} />
          </div>
        ) : list.isLoading ? (
          <div className="space-y-px">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-[72px] rounded-none" />
            ))}
          </div>
        ) : list.data && list.data.rows.length === 0 ? (
          <p className="p-10 text-center text-sm text-muted-foreground">{search ? "No facility matches that search." : "No facility has registered yet."}</p>
        ) : (
          <ul className={cn("divide-y divide-border", list.isFetching && "opacity-70")}>
            {list.data?.rows.map((f) => (
              <li key={f.id}>
                <Link href={`/admin/facilities/${f.id}`} className="flex items-center gap-4 px-4 py-4 transition-colors hover:bg-secondary/60 sm:px-5">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="truncate font-semibold">{f.name}</p>
                      <span
                        className={cn(
                          "rounded-full px-2 py-0.5 text-[11px] font-semibold",
                          f.onboardingStep === "COMPLETED" ? "bg-primary/10 text-primary" : "bg-warning/15 text-warning",
                        )}
                      >
                        {f.onboardingStep === "COMPLETED" ? "Set up" : `Setup: ${humanize(f.onboardingStep)}`}
                      </span>
                      {f.planName && <span className="rounded-full bg-secondary px-2 py-0.5 text-[11px] font-medium">{f.planName}</span>}
                    </div>
                    <p className="mt-0.5 truncate text-sm text-muted-foreground">
                      {f.ownerName ?? "—"} · {f.ownerEmail ?? "—"} · {placeLabel(f.city, f.state)}
                    </p>
                    <p className="mt-0.5 text-xs text-muted-foreground">Registered {formatDate(f.createdAt)}</p>
                  </div>
                  <dl className="hidden shrink-0 grid-cols-4 gap-6 text-center text-sm md:grid">
                    <Metric label="Sports" value={f.sports} />
                    <Metric label="Courts" value={f.courts} />
                    <Metric label="Memberships" value={f.activeMemberships} />
                    <Metric label="Students" value={f.activeStudents} />
                  </dl>
                  <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                </Link>
              </li>
            ))}
          </ul>
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
    </div>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <dd className="text-base font-semibold">{value}</dd>
      <dt className="text-xs text-muted-foreground">{label}</dt>
    </div>
  );
}
