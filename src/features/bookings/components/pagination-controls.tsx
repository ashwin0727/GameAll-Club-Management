"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { SelectField } from "@/components/shared/select-field";
import { pageWindow } from "@/features/bookings/list-utils";
import { cn } from "@/lib/utils";

/**
 * Previous / next arrows, numbered pages (the current one outlined in green, long lists
 * collapsed with "…") and a "10 / page" dropdown.
 */
export function PaginationControls({
  page,
  pages,
  perPage,
  pageSizes,
  onPage,
  onPerPage,
}: {
  page: number;
  pages: number;
  perPage: number;
  pageSizes: number[];
  onPage: (page: number) => void;
  onPerPage: (perPage: number) => void;
}) {
  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        aria-label="Previous page"
        disabled={page <= 1}
        onClick={() => onPage(page - 1)}
        className="flex h-9 w-9 items-center justify-center rounded-[8px] border border-input bg-card text-muted-foreground hover:text-foreground disabled:opacity-40"
      >
        <ChevronLeft className="h-4 w-4" />
      </button>
      {pageWindow(page, pages).map((p, i) =>
        p === "…" ? (
          <span key={`gap-${i}`} className="px-1 text-muted-foreground">
            …
          </span>
        ) : (
          <button
            key={p}
            type="button"
            aria-current={p === page ? "page" : undefined}
            onClick={() => onPage(p)}
            className={cn(
              "h-9 min-w-9 rounded-[8px] border px-2 text-sm font-medium transition-colors",
              p === page
                ? "border-[#0B7A55] text-[#0B7A55] dark:border-primary dark:text-primary"
                : "border-input bg-card text-foreground hover:bg-accent",
            )}
          >
            {p}
          </button>
        ),
      )}
      <button
        type="button"
        aria-label="Next page"
        disabled={page >= pages}
        onClick={() => onPage(page + 1)}
        className="flex h-9 w-9 items-center justify-center rounded-[8px] border border-input bg-card text-muted-foreground hover:text-foreground disabled:opacity-40"
      >
        <ChevronRight className="h-4 w-4" />
      </button>
      <SelectField
        wrapperClassName="w-[120px]"
        ariaLabel="Rows per page"
        value={String(perPage)}
        onValueChange={(v) => onPerPage(Number(v))}
        options={pageSizes.map((n) => ({ value: String(n), label: `${n} / page` }))}
        className="h-9 rounded-[8px] border border-input bg-card pl-3 text-sm outline-none"
      />
    </div>
  );
}
