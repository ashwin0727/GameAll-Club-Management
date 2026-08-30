"use client";

import { useEffect, useMemo, useState } from "react";
import { getMembershipService } from "@/services/memberships";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import type { AssignableBatch } from "@/features/memberships/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import {
  ALL_DAYS,
  WEEKDAYS,
  DAY_OPTIONS,
  sameDays,
  describeBatchOption,
  type NewSlotDraft,
  type SlotSelection,
} from "@/features/memberships/slot-form";

const selectCls = "h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm";

function emptyDraft(sportId: string, days: number[]): NewSlotDraft {
  return { facilitySportId: sportId, courtId: "", daysOfWeek: days, startTime: "06:00", endTime: "07:00", capacity: "" };
}

export function CourtTimeSlotSection({
  value,
  onChange,
  facilityId,
  defaultAccessDays,
}: {
  value: SlotSelection;
  onChange: (s: SlotSelection) => void;
  facilityId: string;
  defaultAccessDays: number[];
}) {
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);
  const [batches, setBatches] = useState<AssignableBatch[]>([]);
  const [facilitySportId, setFacilitySportId] = useState("");

  useEffect(() => {
    let cancelled = false;
    Promise.all([
      getSportsService().getFacilitySports(facilityId),
      getSportsService().getActiveSports(),
      getPlayingAreasService().getPlayingAreas(facilityId),
      getMembershipService().listAssignableBatches(facilityId),
    ])
      .then(([fs, allSports, playingAreas, assignable]) => {
        if (cancelled) return;
        setFacilitySports(fs.filter((f) => f.enabled));
        setSports(allSports);
        setAreas(playingAreas.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
        setBatches(assignable);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [facilityId]);

  const courts = useMemo(
    () => areas.filter((a) => a.facilitySportId === facilitySportId),
    [areas, facilitySportId],
  );
  const courtIds = useMemo(() => new Set(courts.map((c) => c.id)), [courts]);
  const batchesForSport = useMemo(
    () => batches.filter((b) => courtIds.has(b.courtId)),
    [batches, courtIds],
  );

  const draft = value.kind === "new" ? value.draft : null;

  function pickSport(id: string) {
    setFacilitySportId(id);
    if (value.kind === "new") onChange({ kind: "new", draft: emptyDraft(id, value.draft.daysOfWeek) });
    else if (value.kind === "existing") onChange({ kind: "none" });
  }

  function setDraft(patch: Partial<NewSlotDraft>) {
    if (value.kind !== "new") return;
    onChange({ kind: "new", draft: { ...value.draft, ...patch } });
  }

  function toggleDay(day: number) {
    if (!draft) return;
    const next = draft.daysOfWeek.includes(day)
      ? draft.daysOfWeek.filter((d) => d !== day)
      : [...draft.daysOfWeek, day];
    setDraft({ daysOfWeek: next });
  }

  return (
    <div className="space-y-3 rounded-md border border-border p-3">
      <p className="text-xs font-medium text-muted-foreground">
        Court Time Slot <span className="font-normal">(optional — reserves this court/time for the member)</span>
      </p>

      <select
        aria-label="Sport"
        value={facilitySportId}
        onChange={(e) => pickSport(e.target.value)}
        className={selectCls}
      >
        <option value="">Select sport (to add a time slot)</option>
        {facilitySports.map((fs) => {
          const s = sports.find((sp) => sp.id === fs.sportId);
          return (
            <option key={fs.id} value={fs.id}>
              {fs.customSportName ?? s?.name ?? "Sport"}
            </option>
          );
        })}
      </select>

      {facilitySportId && (
        <div className="space-y-2">
          <label className="flex items-start gap-2 text-sm">
            <input
              type="radio"
              name="slot-kind"
              checked={value.kind === "none"}
              onChange={() => onChange({ kind: "none" })}
              className="mt-1"
            />
            <span>No reserved slot</span>
          </label>

          {batchesForSport.map((b) => (
            <label key={b.batchId} className="flex items-start gap-2 text-sm">
              <input
                type="radio"
                name="slot-kind"
                disabled={b.spare <= 0}
                checked={value.kind === "existing" && value.batchId === b.batchId}
                onChange={() => onChange({ kind: "existing", batchId: b.batchId })}
                className="mt-1"
              />
              <span className={b.spare <= 0 ? "text-muted-foreground" : undefined}>
                {b.courtName} · {describeBatchOption(b)}
                {b.spare <= 0 && " — full, raise its capacity in Membership Sessions"}
              </span>
            </label>
          ))}

          <label className="flex items-start gap-2 text-sm">
            <input
              type="radio"
              name="slot-kind"
              checked={value.kind === "new"}
              onChange={() =>
                onChange({ kind: "new", draft: emptyDraft(facilitySportId, defaultAccessDays) })
              }
              className="mt-1"
            />
            <span>+ New time slot</span>
          </label>

          {draft && (
            <div className="ml-6 space-y-2">
              <select
                aria-label="Court"
                value={draft.courtId}
                onChange={(e) => setDraft({ courtId: e.target.value })}
                className={selectCls}
              >
                <option value="">Select court</option>
                {courts.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>

              <div className="flex flex-wrap items-center gap-2">
                {DAY_OPTIONS.map((d) => (
                  <button
                    key={d.value}
                    type="button"
                    onClick={() => toggleDay(d.value)}
                    className={`h-8 rounded-md border px-2 text-xs font-medium ${
                      draft.daysOfWeek.includes(d.value)
                        ? "border-primary bg-primary text-primary-foreground"
                        : "border-input bg-secondary/60"
                    }`}
                  >
                    {d.label}
                  </button>
                ))}
                <button
                  type="button"
                  onClick={() => setDraft({ daysOfWeek: [...ALL_DAYS] })}
                  className={`h-8 rounded-md border px-2 text-xs ${
                    sameDays(draft.daysOfWeek, ALL_DAYS) ? "border-primary text-primary" : "border-input"
                  }`}
                >
                  All 7
                </button>
                <button
                  type="button"
                  onClick={() => setDraft({ daysOfWeek: [...WEEKDAYS] })}
                  className={`h-8 rounded-md border px-2 text-xs ${
                    sameDays(draft.daysOfWeek, WEEKDAYS) ? "border-primary text-primary" : "border-input"
                  }`}
                >
                  Mon–Fri
                </button>
              </div>

              <div className="grid grid-cols-3 gap-2">
                <input
                  aria-label="Start time"
                  type="time"
                  value={draft.startTime}
                  onChange={(e) => setDraft({ startTime: e.target.value })}
                  className={selectCls}
                />
                <input
                  aria-label="End time"
                  type="time"
                  value={draft.endTime}
                  onChange={(e) => setDraft({ endTime: e.target.value })}
                  className={selectCls}
                />
                <input
                  aria-label="Capacity"
                  inputMode="numeric"
                  placeholder="Capacity"
                  value={draft.capacity}
                  onChange={(e) => setDraft({ capacity: e.target.value })}
                  className={selectCls}
                />
              </div>
              <p className="text-[11px] text-muted-foreground">
                How many membership players share this court/time. Owner&apos;s choice — no limit.
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}