import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { MaintenanceTicketsPage } from "@/features/maintenance/components/maintenance-tickets-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Maintenance Tickets — ${APP_NAME}`,
};

export default function TicketsPage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/maintenance" className="hover:text-foreground">
          Maintenance
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Maintenance Tickets</span>
      </nav>
      <MaintenanceTicketsPage />
    </div>
  );
}
