"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { createClient } from "@/lib/supabase/client";
import { getCourtOptions, type CourtOption } from "@/features/maintenance/court-options";
import { formatTime } from "@/features/maintenance/status";
import { getFacilityService } from "@/services/facility";
import { ScheduleDialog } from "@/features/maintenance/components/schedule-dialog";

const DAY_START_HOUR = 8;
const DAY_END_HOUR = 22;
const ROW_HEIGHT = 44; // px per hour

interface GridEvent {
  id: string;
  courtId: string;
  start: Date;
  end: Date;
  kind: "BOOKING" | "MAINTENANCE";
  label: string;
}

function dateInput(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/**
 * A read view over the SAME sources the admin booking grid and Maintenance
 * already write to — bookings + maintenance_blocks, both RLS-scoped direct
 * selects, exactly like the existing booking-operations grid. No second
 * availability algorithm.
 */
export function CourtSchedulePage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [courts, setCourts] = useState<CourtOption[]>([]);
  const [date, setDate] = useState(() => dateInput(new Date()));
  const [events, setEvents] = useState<GridEvent[]>([]);
  const [scheduleCourtId, setScheduleCourtId] = useState<string | null>(null);
  const [scheduleTicketId, setScheduleTicketId] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then(async (f) => {
        if (cancelled) return;
        if (!f) return setLoadState("none");
        setFacilityId(f.id);
        setCourts(await getCourtOptions(f.id));
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  const load = useCallback(async () => {
    if (!facilityId) return;
    const supabase = createClient();
    const dayStart = new Date(`${date}T00:00:00`);
    const dayEnd = new Date(`${date}T23:59:59`);

    const [{ data: bookings }, { data: blocks }] = await Promise.all([
      supabase
        .from("bookings")
        .select("id, court_id, start_time, end_time, status, customer_type, guest_name")
        .eq("facility_id", facilityId)
        .in("status", ["pending", "confirmed"])
        .gte("start_time", dayStart.toISOString())
        .lte("start_time", dayEnd.toISOString()),
      supabase
        .from("maintenance_blocks")
        .select("id, court_id, start_time, end_time, status, ticket_id")
        .eq("facility_id", facilityId)
        .eq("status", "ACTIVE")
        .gte("start_time", dayStart.toISOString())
        .lte("end_time", new Date(dayEnd.getTime() + 24 * 3600 * 1000).toISOString()),
    ]);

    const list: GridEvent[] = [];
    for (const b of bookings ?? []) {
      list.push({
        id: b.id,
        courtId: b.court_id,
        start: new Date(b.start_time),
        end: new Date(b.end_time),
        kind: "BOOKING",
        label: b.customer_type === "GUEST" ? b.guest_name ?? "Guest" : "Member",
      });
    }
    for (const m of blocks ?? []) {
      list.push({ id: m.id, courtId: m.court_id, start: new Date(m.start_time), end: new Date(m.end_time), kind: "MAINTENANCE", label: "Maintenance" });
    }
    setEvents(list);
  }, [facilityId, date]);

  useEffect(() => {
    void load();
  }, [load]);

  const hours = useMemo(() => Array.from({ length: DAY_END_HOUR - DAY_START_HOUR + 1 }, (_, i) => DAY_START_HOUR + i), []);

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load this page. Please try again.</p>;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Court Schedule</h1>
          <p className="text-sm text-muted-foreground">View court availability, maintenance schedules and blocked periods.</p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="icon" onClick={() => setDate(dateInput(new Date(new Date(date).getTime() - 86400000)))}>
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="h-9 rounded-md border border-input bg-background px-2.5 text-sm" />
          <Button variant="outline" size="icon" onClick={() => setDate(dateInput(new Date(new Date(date).getTime() + 86400000)))}>
            <ChevronRight className="h-4 w-4" />
          </Button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-4 text-xs text-muted-foreground">
        <Legend swatch="bg-success/70" label="Available" />
        <Legend swatch="bg-[#5B6CFF]/70" label="Booked" />
        <Legend swatch="bg-destructive/70" label="Under Maintenance" />
      </div>

      <Card className="overflow-hidden p-0">
        <div className="overflow-x-auto">
          <div className="grid" style={{ gridTemplateColumns: `72px repeat(${courts.length}, minmax(140px, 1fr))` }}>
            <div className="border-b border-r border-border bg-secondary/40 p-2 text-xs text-muted-foreground">Time</div>
            {courts.map((c) => (
              <div key={c.id} className="border-b border-r border-border bg-secondary/40 p-2 text-xs font-medium last:border-r-0">
                {c.name}
                <div className="font-normal text-muted-foreground">{c.sportName}</div>
              </div>
            ))}

            {hours.map((h) => (
              <div key={`row-${h}`} className="contents">
                <div className="border-b border-r border-border p-1.5 text-right text-[11px] text-muted-foreground" style={{ height: ROW_HEIGHT }}>
                  {h % 12 === 0 ? 12 : h % 12} {h < 12 ? "AM" : "PM"}
                </div>
                {courts.map((c) => (
                  <div key={`${c.id}-${h}`} className="relative border-b border-r border-border last:border-r-0" style={{ height: ROW_HEIGHT }}>
                    {h === DAY_START_HOUR &&
                      events
                        .filter((e) => e.courtId === c.id)
                        .map((e) => {
                          const startHour = e.start.getHours() + e.start.getMinutes() / 60;
                          const endHour = e.end.getHours() + e.end.getMinutes() / 60;
                          const top = Math.max(0, (startHour - DAY_START_HOUR) * ROW_HEIGHT);
                          const height = Math.max(18, (endHour - Math.max(startHour, DAY_START_HOUR)) * ROW_HEIGHT);
                          return (
                            <button
                              key={e.id}
                              onClick={() => {
                                if (e.kind === "MAINTENANCE") {
                                  setScheduleTicketId(e.id);
                                  setScheduleCourtId(c.id);
                                }
                              }}
                              className={cn(
                                "absolute inset-x-0.5 z-10 overflow-hidden rounded-md px-1.5 py-0.5 text-left text-[11px] text-white",
                                e.kind === "BOOKING" ? "bg-[#5B6CFF]" : "bg-destructive",
                              )}
                              style={{ top, height }}
                              title={`${e.label} · ${formatTime(e.start.toISOString())}–${formatTime(e.end.toISOString())}`}
                            >
                              <span className="block truncate font-medium">{e.label}</span>
                              <span className="block truncate opacity-80">
                                {formatTime(e.start.toISOString())}–{formatTime(e.end.toISOString())}
                              </span>
                            </button>
                          );
                        })}
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>
      </Card>

      {scheduleTicketId && scheduleCourtId && (
        <ScheduleDialog
          open
          onOpenChange={(open) => {
            if (!open) {
              setScheduleTicketId(null);
              setScheduleCourtId(null);
            }
          }}
          ticketId={scheduleTicketId}
          courtId={scheduleCourtId}
          onScheduled={() => void load()}
        />
      )}
    </div>
  );
}

function Legend({ swatch, label }: { swatch: string; label: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span className={cn("h-2.5 w-2.5 rounded-sm", swatch)} /> {label}
    </span>
  );
}
