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
} from "lucide-react";
import { cn } from "@/lib/utils";
import { APP_LOGO_SRC, APP_NAME, APP_SUBTITLE, NAV_ITEMS, type NavItem } from "@/lib/constants";
import type { Role } from "@/types/database.types";
import { useUiStore } from "@/stores/ui-store";

const ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  "/dashboard": LayoutDashboard,
  "/memberships": BadgeIndianRupee,
  "/membership-sessions": CalendarCheck2,
  "/bookings": CalendarClock,
  "/guest-bookings": CalendarRange,
  "/guests": UserRound,
  "/finance": BadgeIndianRupee,
  "/reports": BarChart3,
  "/inventory": Boxes,
};

/**
 * Match the exact path or a real sub-path ("/memberships/new"), never a bare
 * string prefix of a sibling route — "/book" must not light up "/bookings".
 */
function isActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function Sidebar({ role }: { role: Role }) {
  const pathname = usePathname();
  const sidebarOpen = useUiStore((s) => s.sidebarOpen);
  const setSidebarOpen = useUiStore((s) => s.setSidebarOpen);
  const items = NAV_ITEMS.filter((item) => item.roles.includes(role));

  return (
    <>
      {sidebarOpen && (
        <div className="fixed inset-0 z-40 bg-black/50 lg:hidden" onClick={() => setSidebarOpen(false)} />
      )}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-border bg-card transition-transform lg:static lg:translate-x-0",
          sidebarOpen ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="flex h-16 items-center gap-2.5 border-b border-border px-4">
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

        <nav className="flex-1 space-y-1 overflow-y-auto p-3">
          {items.map((item) =>
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
        </nav>
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
