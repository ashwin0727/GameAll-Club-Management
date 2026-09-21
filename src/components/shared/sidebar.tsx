"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import {
  LayoutDashboard,
  CalendarClock,
  Boxes,
  UserRound,
  CalendarCheck2,
  BadgeIndianRupee,
  BarChart3,
  CalendarRange,
  ChevronDown,
  Wrench,
  ShieldCheck,
  Crown,
  Dumbbell,
  Trophy,
  Users,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { APP_LOGO_SRC, APP_NAME, APP_SUBTITLE, NAV_GROUP_LABELS, NAV_ITEMS, type NavGroup, type NavItem } from "@/lib/constants";
import type { Role } from "@/types/database.types";
import { useUiStore } from "@/stores/ui-store";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { PermissionKey } from "@/features/staff/types";

const ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  "/dashboard": LayoutDashboard,
  "/memberships": Users,
  "/membership-sessions": CalendarCheck2,
  "/calendar": CalendarClock,
  "/guest-bookings": CalendarRange,
  "/guests": UserRound,
  "/finance": BadgeIndianRupee,
  "/reports": BarChart3,
  "/maintenance": Wrench,
  "/users-roles/staff": ShieldCheck,
  "/inventory": Boxes,
  "/coaching": Dumbbell,
  "/tournaments": Trophy,
};

/**
 * Match the exact path or a real sub-path ("/memberships/new"), never a bare
 * string prefix of a sibling route — "/book" must not light up "/bookings" or "/calendar".
 */
function isActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}

const GROUP_ORDER: NavGroup[] = ["main", "club", "operations", "finance"];

export function Sidebar({ role }: { role: Role }) {
  const pathname = usePathname();
  const sidebarOpen = useUiStore((s) => s.sidebarOpen);
  const setSidebarOpen = useUiStore((s) => s.setSidebarOpen);
  const perms = usePermissionContext();
  const items = NAV_ITEMS.filter(
    (item) =>
      item.roles.includes(role) &&
      // A permission-gated section is hidden until the user holds the key for
      // the active facility (or there is no permission context yet — e.g.
      // mid-onboarding — in which case fall back to the role gate above).
      (!item.permission || !perms || perms.can(item.permission as PermissionKey)),
  );

  return (
    <>
      {sidebarOpen && (
        <div className="fixed inset-0 z-40 bg-black/50 lg:hidden" onClick={() => setSidebarOpen(false)} />
      )}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 flex w-56 flex-col border-r border-border/40 bg-[var(--light-page-bg)] transition-transform dark:bg-card lg:static lg:translate-x-0",
          sidebarOpen ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="flex h-16 items-center gap-2.5 border-b border-border/40 px-4">
          <Image
            src={APP_LOGO_SRC}
            alt=""
            aria-hidden
            width={512}
            height={512}
            priority
            className="h-9 w-9 object-contain"
          />
          <span className="flex flex-col leading-tight">
            <span className="font-semibold">{APP_NAME}</span>
            <span className="text-[11px] text-muted-foreground">{APP_SUBTITLE}</span>
          </span>
        </div>

        <nav className="flex-1 space-y-4 overflow-y-auto p-3">
          {GROUP_ORDER.map((group) => {
            const groupItems = items.filter((item) => item.group === group);
            if (groupItems.length === 0) return null;
            const heading = NAV_GROUP_LABELS[group];
            return (
              <div key={group} className="space-y-1">
                {heading && (
                  <p className="px-3 pb-1 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/80">
                    {heading}
                  </p>
                )}
                {groupItems.map((item) =>
                  item.children?.length ? (
                    <NavSection
                      key={item.href}
                      item={item}
                      pathname={pathname}
                      onNavigate={() => setSidebarOpen(false)}
                    />
                  ) : (
                    <NavLink
                      key={item.href}
                      href={item.href}
                      label={item.label}
                      icon={ICONS[item.href] ?? LayoutDashboard}
                      active={isActive(pathname, item.href)}
                      onNavigate={() => setSidebarOpen(false)}
                    />
                  ),
                )}
              </div>
            );
          })}
        </nav>

        {/* Promo only — there is no billing/plans route to link to yet. */}
        <div className="m-3 space-y-2 rounded-xl border border-border bg-secondary/40 p-3">
          <Crown className="h-4 w-4 text-warning" aria-hidden />
          <p className="text-xs font-semibold text-foreground">Upgrade Your Club</p>
          <p className="text-[11px] leading-snug text-muted-foreground">
            Unlock advanced features and grow faster.
          </p>
          <button
            type="button"
            disabled
            className="h-8 w-full rounded-md border border-border bg-card text-xs font-medium text-foreground opacity-80"
          >
            View Plans
          </button>
        </div>
      </aside>
    </>
  );
}

/**
 * A section that expands to reveal its pages. It opens itself whenever one
 * of them is the current page, so arriving by link or reload never leaves
 * the section collapsed around the page you are on.
 */
function NavSection({
  item,
  pathname,
  onNavigate,
}: {
  item: NavItem;
  pathname: string;
  onNavigate: () => void;
}) {
  const children = item.children ?? [];
  const sectionActive =
    isActive(pathname, item.href) || children.some((child) => isActive(pathname, child.href));
  const [open, setOpen] = useState(sectionActive);

  useEffect(() => {
    if (sectionActive) setOpen(true);
  }, [sectionActive]);

  const Icon = ICONS[item.href] ?? LayoutDashboard;

  return (
    <div>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className={cn(
          "flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
          sectionActive
            ? "bg-primary/10 text-primary"
            : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
        )}
      >
        <Icon className="h-4 w-4 shrink-0" />
        <span className="flex-1 text-left">{item.label}</span>
        <ChevronDown className={cn("h-4 w-4 shrink-0 transition-transform", open && "rotate-180")} aria-hidden />
      </button>

      {open && (
        <ul className="mt-1 space-y-0.5">
          {children.map((child) => {
            // Overview shares the section's own href, so it must match
            // exactly or every Finance page would light it up too.
            const active =
              child.href === item.href ? pathname === child.href : isActive(pathname, child.href);
            return (
              <li key={child.href}>
                <Link
                  href={child.href}
                  onClick={onNavigate}
                  className={cn(
                    "block rounded-md py-1.5 pl-10 pr-3 text-sm transition-colors",
                    active
                      ? "font-medium text-primary"
                      : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                  )}
                >
                  {child.label}
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function NavLink({
  href,
  label,
  icon: Icon,
  active,
  onNavigate,
}: {
  href: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  active: boolean;
  onNavigate: () => void;
}) {
  return (
    <Link
      href={href}
      onClick={onNavigate}
      className={cn(
        "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
        active
          ? "bg-primary text-primary-foreground"
          : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
      )}
    >
      <Icon className="h-4 w-4" />
      {label}
    </Link>
  );
}
