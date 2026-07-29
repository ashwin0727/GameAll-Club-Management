"use client";

import { Menu, LogOut, User } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useUiStore } from "@/stores/ui-store";
import { useLogout } from "@/features/auth/hooks/use-auth";
import { getInitials } from "@/lib/utils";
import type { Profile } from "@/features/auth/types";

export function Topbar({ profile }: { profile: Profile }) {
  const toggleSidebar = useUiStore((s) => s.toggleSidebar);
  const logout = useLogout();

  return (
    <header className="flex h-14 items-center justify-between border-b border-border bg-background px-4">
      <Button variant="ghost" size="icon" className="lg:hidden" onClick={toggleSidebar}>
        <Menu className="h-5 w-5" />
      </Button>
      <div className="hidden lg:block" />
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button className="flex items-center gap-2 rounded-full outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <Avatar>
              <AvatarFallback>{getInitials(profile.full_name)}</AvatarFallback>
            </Avatar>
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuLabel className="flex flex-col">
            <span className="font-medium">{profile.full_name}</span>
            <span className="text-xs font-normal capitalize text-muted-foreground">
              {profile.role}
            </span>
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