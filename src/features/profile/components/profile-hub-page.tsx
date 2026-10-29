"use client";

import { useState } from "react";
import Link from "next/link";
import { CalendarCheck, ChevronRight, Building2, CreditCard, Grid2x2, Headset, HeartHandshake, IndianRupee, LogOut, Settings, User, Users } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { DeleteAccountDialog } from "@/features/account/delete-account";
import { LogoutConfirm } from "@/features/auth/components/logout-confirm";
import type { Profile } from "@/features/auth/types";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { formatCurrency } from "@/features/pricing/money";
import { useFacilityPlan, useProfileStats } from "@/features/profile/hooks";
import { PlanCard } from "@/features/profile/components/plan-card";
import { ProfileHero } from "@/features/profile/components/profile-hero";
import { Button } from "@/components/ui/button";

interface Option {
  href: string;
  title: string;
  description: string;
  icon: React.ComponentType<{ className?: string }>;
  /** Extra classes for the glyph (the person is a solid shape in the design). */
  iconClass?: string;
}

const OPTIONS: Option[] = [
  {
    href: "/profile/personal",
    title: "Personal Information",
    description: "View and manage your personal details, contact information and profile photo.",
    icon: User,
    iconClass: "fill-current",
  },
  {
    href: "/profile/facility",
    title: "Manage Facility Details",
    description: "View and manage your facility details, courts, sports, timings, payout and more.",
    icon: Building2,
  },
  {
    href: "/profile/payments",
    title: "Payment Methods",
    description: "Manage your bank accounts and payment methods to receive payouts.",
    icon: CreditCard,
  },
  {
    href: "/profile/support",
    title: "Help & Support",
    description: "Get help, raise a support ticket or view FAQs.",
    icon: Headset,
  },
  {
    href: "/profile/settings",
    title: "Settings",
    description: "Manage your notification preferences, security and other settings.",
    icon: Settings,
  },
];

function OptionCard({ option, className }: { option: Option; className?: string }) {
  const Icon = option.icon;
  return (
    <Link
      href={option.href}
      className={`group block rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring ${className ?? ""}`}
    >
      <Card className="flex h-full items-start gap-4 p-4 transition-all group-hover:-translate-y-0.5 group-hover:shadow-md sm:p-5">
        {/* The same soft blue badge on every option, as in the design. */}
        <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-blue-100 text-blue-600 dark:bg-blue-500/15 dark:text-blue-400">
          <Icon className={`h-6 w-6 ${option.iconClass ?? ""}`} />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-[15px] font-semibold">{option.title}</span>
          <span className="mt-1 block text-[13px] leading-relaxed text-muted-foreground">{option.description}</span>
        </span>
        <ChevronRight
          className="mt-1 h-5 w-5 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5"
          aria-hidden
        />
      </Card>
    </Link>
  );
}

/** One of the four totals: an icon badge, then the figure above its label — as in the design. Bookings and revenue are for the current month. */
function StatTile({
  icon: Icon,
  tint,
  value,
  label,
  hint,
  round = false,
}: {
  icon: React.ComponentType<{ className?: string }>;
  tint: string;
  value: string;
  label: string;
  hint?: string;
  round?: boolean;
}) {
  return (
    <div className="flex min-w-0 items-center gap-3 rounded-xl bg-sky-50/80 p-3 dark:bg-muted/50">
      <span className={`flex h-10 w-10 shrink-0 items-center justify-center ${round ? "rounded-full" : "rounded-lg"} ${tint}`}>
        <Icon className="h-5 w-5" />
      </span>
      <div className="min-w-0">
        <p className="truncate text-lg font-semibold leading-tight">{value}</p>
        <p className="truncate text-xs text-muted-foreground">{label}</p>
        {hint && <p className="truncate text-[11px] text-muted-foreground/80">{hint}</p>}
      </div>
    </div>
  );
}

/** Profile: who you are, your GameAll plan, how the facility is doing, and the doors into everything else. */
export function ProfileHubPage({ profile }: { profile: Profile }) {
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const plan = useFacilityPlan(facility?.id);
  const stats = useProfileStats(facility?.id);
  const [confirmLogout, setConfirmLogout] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const s = stats.data;

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold">Profile</h1>
        <p className="text-sm text-muted-foreground">Manage your account, facility information and preferences</p>
      </div>

      <ProfileHero profile={profile} />

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)]">
        <PlanCard
          plan={plan.data}
          loading={facilityLoading || plan.isLoading}
          facilityName={facility?.name ?? "Your facility"}
          error={plan.isError}
        />

        <Card className="p-3 sm:p-4">
          {stats.isLoading || facilityLoading ? (
            <div className="grid grid-cols-2 gap-3">
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="h-[76px] rounded-xl" />
              ))}
            </div>
          ) : s ? (
            <div className="grid grid-cols-2 gap-3">
              <StatTile icon={CalendarCheck} tint="bg-blue-500/15 text-blue-600 dark:text-blue-400" value={s.totalBookings.toLocaleString("en-IN")} label="Total Bookings" hint="This Month" />
              <StatTile icon={Users} tint="bg-blue-500/15 text-blue-600 dark:text-blue-400" value={s.activeMembers.toLocaleString("en-IN")} label="Active Members" />
              <StatTile icon={Grid2x2} tint="bg-amber-500/15 text-amber-600 dark:text-amber-400" value={s.courts.toLocaleString("en-IN")} label="Courts / Turfs" />
              <StatTile icon={IndianRupee} round tint="bg-emerald-500 text-white" value={formatCurrency(s.totalRevenueMinor, "INR")} label="Total Revenue" hint="This Month" />
            </div>
          ) : (
            <p className="flex h-full items-center justify-center py-8 text-center text-sm text-muted-foreground">
              Your facility numbers are unavailable right now.
            </p>
          )}
        </Card>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-6">
        {OPTIONS.map((o, i) => (
          <OptionCard key={o.href} option={o} className={i < 3 ? "xl:col-span-2" : "xl:col-span-3"} />
        ))}
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card p-4">
        <p className="flex items-center gap-2 text-sm text-muted-foreground">
          <HeartHandshake className="h-4 w-4 text-primary" aria-hidden />
          Signed in as <span className="font-medium text-foreground">{profile.email}</span>
        </p>
        <Button
          type="button"
          variant="outline"
          className="border-destructive/40 text-destructive hover:bg-destructive/10 hover:text-destructive"
          onClick={() => setConfirmLogout(true)}
        >
          <LogOut className="mr-1.5 h-4 w-4" aria-hidden /> Log out
        </Button>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 pt-2 text-xs text-muted-foreground">
        <span className="flex gap-4">
          <Link href="/privacy" className="hover:text-foreground hover:underline">
            Privacy policy
          </Link>
          <Link href="/terms" className="hover:text-foreground hover:underline">
            Terms of service
          </Link>
        </span>
        <button
          type="button"
          onClick={() => setConfirmDelete(true)}
          className="text-destructive/80 underline-offset-4 hover:text-destructive hover:underline"
        >
          Delete account
        </button>
      </div>

      <LogoutConfirm open={confirmLogout} facilityName={facility?.name} onCancel={() => setConfirmLogout(false)} />
      <DeleteAccountDialog open={confirmDelete} onClose={() => setConfirmDelete(false)} />
    </div>
  );
}
