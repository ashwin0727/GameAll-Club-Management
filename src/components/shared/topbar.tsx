"use client";

import { useEffect, useState } from "react";
import { Bell, Building2, CalendarDays, Check, ChevronDown, LogOut, Menu, User } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { TopbarSearch } from "@/components/shared/topbar-search";
import { useUiStore } from "@/stores/ui-store";
import { useLogout } from "@/features/auth/hooks/use-auth";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useSportFilter } from "@/features/facility/hooks/use-sport-filter";
import { sportSelectionLabel } from "@/features/facility/sport-selection";
import { cn, getInitials } from "@/lib/utils";
import type { Profile } from "@/features/auth/types";

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "Mon, 15 Sep 2026" — the design's date chip. */
function formatToday(d: Date): string {
  return `${WEEKDAYS[d.getDay()]}, ${String(d.getDate()).padStart(2, "0")} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** The facility owner signs in as an admin; the design labels that role "Owner". */
const ROLE_LABEL: Record<Profile["role"], string> = { admin: "Owner", staff: "Staff", member: "Member" };

const CHIP = "flex h-10 items-center gap-2 rounded-lg border border-border bg-card px-3 text-sm";

export function Topbar({ profile }: { profile: Profile }) {
  const toggleSidebar = useUiStore((s) => s.toggleSidebar);
  const logout = useLogout();
  const { data: facility } = useFacility();
  // "All Sports" by default; the user can tick any combination and every page follows.
  const sports = useSportFilter(facility?.id);
  const sportLabel = sportSelectionLabel(
    { ids: sports.selectedIds, isAll: sports.isAll },
    new Map(sports.options.map((o) => [o.facilitySportId, o.name])),
  );
  // Read on the client only, so the server-rendered HTML never disagrees with
  // the browser's clock or timezone.
  const [today, setToday] = useState<string | null>(null);
  useEffect(() => setToday(formatToday(new Date())), []);

  // h-16 matches the sidebar's brand header, so the two bottom borders read
  // as one continuous line across the top of the app.
  return (
    <header className="flex h-16 items-center gap-3 border-b border-border/40 bg-background px-4">
      <Button variant="ghost" size="icon" className="lg:hidden" onClick={toggleSidebar} aria-label="Open Menu">
        <Menu className="h-5 w-5" />
      </Button>

      {/* Facility — fixed: there is one facility here, so nothing to switch. */}
      <div className={cn(CHIP, "min-w-0 max-w-[220px]")} aria-label="Facility">
        <Building2 className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
        <span className="truncate font-medium">{facility?.name ?? "Your facility"}</span>
      </div>

      {/* Sports — All Sports by default; tick any combination to look at just those. */}
      {sports.options.length > 0 && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              aria-label="Sports"
              className={cn(CHIP, "min-w-0 max-w-[240px] outline-none focus-visible:ring-2 focus-visible:ring-ring")}
            >
              <span className="truncate font-medium">{sportLabel}</span>
              <ChevronDown className="ml-1 h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-64">
            <DropdownMenuLabel className="text-xs font-normal text-muted-foreground">Show data for</DropdownMenuLabel>
            <DropdownMenuCheckboxItem
              checked={sports.isAll}
              // Keep the menu open so several sports can be ticked in one go.
              onSelect={(e) => e.preventDefault()}
              onCheckedChange={() => sports.selectAll()}
            >
              <span className="font-medium">All Sports</span>
            </DropdownMenuCheckboxItem>
            <DropdownMenuSeparator />
            {sports.options.map((option) => (
              <DropdownMenuCheckboxItem
                key={option.facilitySportId}
                checked={sports.selectedIds.includes(option.facilitySportId)}
                onSelect={(e) => e.preventDefault()}
                onCheckedChange={() => sports.toggle(option.facilitySportId)}
              >
                <span className="mr-2" aria-hidden>
                  {option.icon}
                </span>
                {option.name}
              </DropdownMenuCheckboxItem>
            ))}
            {!sports.isAll && (
              <p className="flex items-center gap-1.5 px-2 pb-1.5 pt-2 text-[11px] text-muted-foreground">
                <Check className="h-3 w-3" aria-hidden /> Every page shows only the sports ticked above.
              </p>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      )}

      <div className="flex-1" />

      {/* Date */}
      <div className={cn(CHIP, "hidden lg:flex")} aria-label="Today's Date">
        <CalendarDays className="h-4 w-4 text-muted-foreground" aria-hidden />
        <span className="whitespace-nowrap tabular-nums">{today ?? " "}</span>
      </div>

      <TopbarSearch role={profile.role} />

      {/* Notifications — there is no notification feed yet, so no badge is shown. */}
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            aria-label="Notifications"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-border bg-card text-muted-foreground outline-none transition-colors hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
          >
            <Bell className="h-4 w-4" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-64">
          <DropdownMenuLabel>Notifications</DropdownMenuLabel>
          <DropdownMenuSeparator />
          <p className="px-2 py-3 text-center text-xs text-muted-foreground">You&apos;re all caught up.</p>
        </DropdownMenuContent>
      </DropdownMenu>

      <div className="hidden h-8 w-px bg-border sm:block" aria-hidden />

      {/* Account */}
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button className="flex items-center gap-2.5 rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <Avatar className="h-9 w-9">
              <AvatarFallback className="bg-primary text-sm font-semibold text-primary-foreground">
                {getInitials(profile.full_name)}
              </AvatarFallback>
            </Avatar>
            <span className="hidden min-w-0 flex-col text-left leading-tight sm:flex">
              <span className="max-w-[9rem] truncate text-sm font-semibold">{profile.full_name}</span>
              <span className="text-xs text-muted-foreground">{ROLE_LABEL[profile.role]}</span>
            </span>
            <ChevronDown className="hidden h-4 w-4 text-muted-foreground sm:block" aria-hidden />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuLabel className="flex flex-col">
            <span className="font-medium">{profile.full_name}</span>
            <span className="text-xs font-normal text-muted-foreground">{ROLE_LABEL[profile.role]}</span>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem disabled className="gap-2">
            <User className="h-4 w-4" />
            Profile
          </DropdownMenuItem>
          <DropdownMenuItem
            className="gap-2 text-destructive focus:text-destructive"
            onClick={() => logout.mutate()}
          >
            <LogOut className="h-4 w-4" />
            Sign out
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </header>
  );
}
