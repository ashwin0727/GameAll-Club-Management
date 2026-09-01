"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, CalendarClock, Boxes, UserRound, CalendarCheck2, BadgeIndianRupee, CalendarRange } from "lucide-react";
import { cn } from "@/lib/utils";
import { APP_LOGO_SRC, APP_NAME, APP_SUBTITLE, NAV_ITEMS } from "@/lib/constants";
import type { Role } from "@/types/database.types";
import { useUiStore } from "@/stores/ui-store";

const ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  "/dashboard": LayoutDashboard,
  "/memberships": BadgeIndianRupee,
  "/membership-sessions": CalendarCheck2,
  "/bookings": CalendarClock,
  "/guest-bookings": CalendarRange,
  "/guests": UserRound,
  "/inventory": Boxes,
};

export function Sidebar({ role }: { role: Role }) {
  const pathname = usePathname();
  const sidebarOpen = useUiStore((s) => s.sidebarOpen);
  const setSidebarOpen = useUiStore((s) => s.setSidebarOpen);
  const items = NAV_ITEMS.filter((item) => item.roles.includes(role));

  return (
    <>
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/50 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-border bg-card transition-transform lg:static lg:translate-x-0",
          sidebarOpen ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="flex h-16 items-center gap-2.5 border-b border-border px-4">
          <Image src={APP_LOGO_SRC} alt="" aria-hidden width={512} height={512} priority className="h-9 w-9 object-contain" />
          <span className="flex flex-col leading-tight">
            <span className="font-semibold">{APP_NAME}</span>
            <span className="text-[11px] text-muted-foreground">{APP_SUBTITLE}</span>
          </span>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {items.map((item) => {
            const Icon = ICONS[item.href] ?? LayoutDashboard;
            // Match the exact path or a real sub-path ("/memberships/new"),
            // never a bare string prefix of a sibling route.
            const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setSidebarOpen(false)}
                className={cn(
                  "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                  active
                    ? "bg-primary text-primary-foreground"
                    : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                )}
              >
                <Icon className="h-4 w-4" />
                {item.label}
              </Link>
            );
          })}
        </nav>
      </aside>
    </>
  );
}