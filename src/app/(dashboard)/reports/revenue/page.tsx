import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { RevenueReport } from "@/features/reports/components/revenue-report";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Revenue Report — ${APP_NAME}` };

export default function ReportsRevenuePage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/reports" className="hover:text-foreground">
          Reports
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Revenue</span>
      </nav>
      <RevenueReport />
    </div>
  );
}
