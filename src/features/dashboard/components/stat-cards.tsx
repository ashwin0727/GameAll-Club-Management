"use client";

import { motion } from "framer-motion";
import { Users, IdCard, CalendarClock, Wallet } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatCardSkeleton } from "@/components/shared/loading-state";
import { ErrorState } from "@/components/shared/error-state";
import { useDashboardStats } from "@/features/dashboard/hooks/use-dashboard-stats";
import { formatCurrencyINR, cn } from "@/lib/utils";

const CARDS = [
  { key: "totalMembers" as const, label: "Total Members", icon: Users, format: (v: number) => v.toString() },
  {
    key: "activeMemberships" as const,
    label: "Active Memberships",
    icon: IdCard,
    format: (v: number) => v.toString(),
  },
  {
    key: "activeBookingsToday" as const,
    label: "Bookings Today",
    icon: CalendarClock,
    format: (v: number) => v.toString(),
  },
  {
    key: "revenueThisMonthInr" as const,
    label: "Revenue This Month",
    icon: Wallet,
    format: (v: number) => formatCurrencyINR(v),
  },
];

export function StatCards() {
  const { data, isLoading, isError, refetch } = useDashboardStats();

  if (isLoading) {
    return (
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {CARDS.map((c) => (
          <StatCardSkeleton key={c.key} />
        ))}
      </div>
    );
  }

  if (isError || !data) {
    return <ErrorState message="Couldn't load dashboard stats." onRetry={() => refetch()} />;
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {CARDS.map((card, index) => (
        <motion.div
          key={card.key}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.25, delay: index * 0.05 }}
        >
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                {card.label}
              </CardTitle>
              <card.icon className={cn("h-4 w-4 text-primary")} />
            </CardHeader>
            <CardContent>
              <p className="text-2xl font-semibold">{card.format(data[card.key])}</p>
            </CardContent>
          </Card>
        </motion.div>
      ))}
    </div>
  );
}