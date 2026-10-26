"use client";

import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bell, CalendarCheck2, CircleAlert, GraduationCap, LineChart, Ticket } from "lucide-react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { createClient } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";

interface AppNotification {
  id: string;
  kind: string;
  title: string;
  body: string;
  createdAt: string;
  read: boolean;
  route: string | null;
}

const KEYS = { list: ["notifications", "list"] as const };

// notifications (migration 0161) is newer than the generated database types, hence the casts. Row-level security
// returns only the signed-in person's own rows.
type Query = {
  from: (t: string) => {
    select: (c: string) => {
      order: (c: string, o: { ascending: boolean }) => { limit: (n: number) => Promise<{ data: Record<string, unknown>[] | null; error: unknown }> };
    };
  };
  rpc: (fn: string, args?: Record<string, unknown>) => Promise<{ error: unknown }>;
};

async function loadNotifications(): Promise<AppNotification[]> {
  const supabase = createClient() as unknown as Query;
  const { data, error } = await supabase.from("notifications").select("id, kind, title, body, data, created_at, read_at").order("created_at", { ascending: false }).limit(30);
  if (error) throw new Error("Unable to load notifications.");
  return (data ?? []).map((r) => ({
    id: r.id as string,
    kind: r.kind as string,
    title: r.title as string,
    body: r.body as string,
    createdAt: r.created_at as string,
    read: r.read_at != null,
    route: ((r.data as { route?: string } | null)?.route as string | undefined) ?? null,
  }));
}

async function markRead(ids: string[] | null): Promise<void> {
  const supabase = createClient() as unknown as Query;
  await supabase.rpc("mark_notifications_read", { p_ids: ids });
}

function iconFor(kind: string) {
  if (kind.startsWith("guest_booking")) return Ticket;
  if (kind.startsWith("membership")) return CalendarCheck2;
  if (kind.startsWith("coaching")) return GraduationCap;
  if (kind === "monthly_report") return LineChart;
  return Bell;
}

function isProblem(kind: string) {
  return kind.includes("failed") || kind.includes("not_renewed");
}

function ago(iso: string): string {
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60_000);
  if (mins < 1) return "Just now";
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} h ago`;
  const days = Math.floor(hours / 24);
  return days < 7 ? `${days} d ago` : new Date(iso).toLocaleDateString("en-IN", { day: "numeric", month: "short" });
}

/** The topbar bell: unread count, the latest messages, tap to open the page one is about. Refreshes every 30 seconds. */
export function NotificationBell() {
  const router = useRouter();
  const qc = useQueryClient();
  const { data = [] } = useQuery({ queryKey: KEYS.list, queryFn: loadNotifications, refetchInterval: 30_000, retry: false });
  const unread = data.filter((n) => !n.read).length;
  const read = useMutation({ mutationFn: markRead, onSuccess: () => qc.invalidateQueries({ queryKey: KEYS.list }) });

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          aria-label={unread > 0 ? `Notifications, ${unread} unread` : "Notifications"}
          className="relative flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-border bg-card text-muted-foreground outline-none transition-colors hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
        >
          <Bell className="h-4 w-4" />
          {unread > 0 && (
            <span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[10px] font-semibold leading-none text-destructive-foreground">
              {unread > 9 ? "9+" : unread}
            </span>
          )}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-[22rem] max-w-[calc(100vw-1.5rem)] p-0">
        <div className="flex items-center justify-between px-3 py-2.5">
          <DropdownMenuLabel className="p-0">Notifications</DropdownMenuLabel>
          {unread > 0 && (
            <button type="button" onClick={() => read.mutate(null)} className="text-xs font-medium text-primary hover:underline">
              Mark all read
            </button>
          )}
        </div>
        <DropdownMenuSeparator className="m-0" />
        {data.length === 0 ? (
          <p className="px-3 py-8 text-center text-sm text-muted-foreground">You&apos;re all caught up.</p>
        ) : (
          <ul className="max-h-96 overflow-y-auto">
            {data.map((n) => {
              const Icon = isProblem(n.kind) ? CircleAlert : iconFor(n.kind);
              return (
                <li key={n.id}>
                  <button
                    type="button"
                    onClick={() => {
                      if (!n.read) read.mutate([n.id]);
                      if (n.route) router.push(n.route);
                    }}
                    className={cn("flex w-full items-start gap-3 border-b border-border px-3 py-3 text-left transition-colors last:border-b-0 hover:bg-secondary/60", !n.read && "bg-primary/5")}
                  >
                    <span className={cn("mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full", isProblem(n.kind) ? "bg-destructive/10 text-destructive" : "bg-primary/10 text-primary")}>
                      <Icon className="h-4 w-4" aria-hidden />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="flex items-center justify-between gap-2">
                        <span className={cn("text-sm", n.read ? "font-medium" : "font-semibold")}>{n.title}</span>
                        <span className="shrink-0 text-[11px] text-muted-foreground">{ago(n.createdAt)}</span>
                      </span>
                      <span className="mt-0.5 block text-[13px] leading-snug text-muted-foreground">{n.body}</span>
                    </span>
                    {!n.read && <span className="mt-2 h-2 w-2 shrink-0 rounded-full bg-primary" aria-hidden />}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
