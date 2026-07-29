import { Loader2 } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

export function LoadingSpinner({ className }: { className?: string }) {
  return (
    <div className={cn("flex items-center justify-center py-12 text-muted-foreground", className)}>
      <Loader2 className="h-5 w-5 animate-spin" />
    </div>
  );
}

export function TableSkeleton({ rows = 5, columns = 4 }: { rows?: number; columns?: number }) {
  return (
    <div className="space-y-3">
      {Array.from({ length: rows }).map((_, rowIndex) => (
        <div key={rowIndex} className="flex items-center gap-4">
          {Array.from({ length: columns }).map((__, colIndex) => (
            <Skeleton key={colIndex} className="h-9 flex-1" />
          ))}
        </div>
      ))}
    </div>
  );
}

export function StatCardSkeleton() {
  return (
    <div className="rounded-xl border border-border bg-card p-6">
      <Skeleton className="h-4 w-24" />
      <Skeleton className="mt-3 h-8 w-16" />
    </div>
  );
}