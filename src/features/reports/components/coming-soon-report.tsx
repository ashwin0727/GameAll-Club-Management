"use client";

import { useAnalyticsFilter } from "./use-analytics-filter";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { AnalyticsFilterSheet } from "./analytics-filter-sheet";
import { ReportShell } from "./report-shell";

/**
 * The report frame with the real filter bar, an empty body. Each phase
 * replaces the body (and flips `status` to loading/ready) for its report but
 * keeps this exact shell + filter wiring.
 */
export function ComingSoonReport({
  title,
  description,
  emptyMessage = "This report arrives in a later phase.",
}: {
  title: string;
  description: string;
  emptyMessage?: string;
}) {
  const { filter, setFilter, ready } = useAnalyticsFilter();

  const filterBar =
    ready && filter ? (
      <>
        <div className="hidden md:block">
          <AnalyticsFilterBar filter={filter} onChange={setFilter} />
        </div>
        <div className="md:hidden">
          <AnalyticsFilterSheet filter={filter} onChange={setFilter} />
        </div>
      </>
    ) : null;

  return (
    <ReportShell
      title={title}
      description={description}
      status={ready ? "empty" : "loading"}
      emptyMessage={emptyMessage}
      filterBar={filterBar}
    >
      <div />
    </ReportShell>
  );
}
