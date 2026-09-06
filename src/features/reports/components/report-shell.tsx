"use client";

import { AlertCircle, Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export type ReportStatus = "loading" | "error" | "empty" | "ready";

/**
 * Every report page's frame. The header always renders; the body switches on
 * `status` so "still loading", "loaded but empty" and "failed" are always
 * visually distinct and a figure never flashes as 0 mid-load (spec §43/§44/§45).
 */
export function ReportShell({
  title,
  description,
  status,
  onRetry,
  emptyMessage = "No data for this period.",
  errorMessage = "Unable to load this report. Please try again.",
  filterBar,
  onExportCsv,
  children,
}: {
  title: string;
  description: string;
  status: ReportStatus;
  onRetry?: () => void;
  emptyMessage?: string;
  errorMessage?: string;
  filterBar?: React.ReactNode;
  onExportCsv?: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">{title}</h1>
          <p className="text-sm text-muted-foreground">{description}</p>
        </div>
        {status === "ready" && onExportCsv && (
          <Button variant="outline" size="sm" className="min-h-9" onClick={onExportCsv}>
            <Download className="h-4 w-4" aria-hidden /> Download CSV
          </Button>
        )}
      </div>

      {filterBar}

      {status === "loading" && (
        <div className="space-y-4" aria-busy>
          <Skeleton className="h-24 w-full rounded-xl" />
          <Skeleton className="h-64 w-full rounded-xl" />
          <Skeleton className="h-64 w-full rounded-xl" />
        </div>
      )}

      {status === "error" && (
        <Card className="flex flex-col items-center gap-3 border-destructive/40 p-10 text-center">
          <AlertCircle className="h-6 w-6 text-destructive" aria-hidden />
          <p className="text-sm text-muted-foreground">{errorMessage}</p>
          {onRetry && (
            <Button variant="outline" size="sm" onClick={onRetry}>
              Try again
            </Button>
          )}
        </Card>
      )}

      {status === "empty" && (
        <Card className="border-dashed p-10 text-center">
          <p className="text-sm text-muted-foreground">{emptyMessage}</p>
        </Card>
      )}

      {status === "ready" && children}
    </div>
  );
}
