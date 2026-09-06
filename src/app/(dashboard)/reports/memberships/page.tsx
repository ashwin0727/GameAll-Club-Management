import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { MembershipReport } from "@/features/reports/components/membership-report";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Membership Report — ${APP_NAME}` };

export default function ReportsMembershipsPage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/reports" className="hover:text-foreground">
          Reports
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Memberships</span>
      </nav>
      <MembershipReport />
    </div>
  );
}
