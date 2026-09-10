import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { DailyClosingPage } from "@/features/finance/components/daily-closing-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Daily Closing — ${APP_NAME}`,
};

export default function FinanceDailyClosingPage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/finance" className="hover:text-foreground">
          Finance
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Daily Closing</span>
      </nav>
      <DailyClosingPage />
    </div>
  );
}
