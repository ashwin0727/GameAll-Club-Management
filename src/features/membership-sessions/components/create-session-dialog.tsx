"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getMembershipService } from "@/services/memberships";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { ServiceError } from "@/services/shared/service-error";
import type { MembershipPlan } from "@/features/memberships/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";

const DAYS = [
  { value: 1, label: "Mon" },
  { value: 2, label: "Tue" },
  { value: 3, label: "Wed" },
  { value: 4, label: "Thu" },
  { value: 5, label: "Fri" },
  { value: 6, label: "Sat" },
  { value: 0, label: "Sun" },
];
const selectCls = "h-10 w-full rounded-md border border-input bg-secondary/60 px-3 text-sm";

export function CreateSessionDialog({
  open,
  onOpenChange,
  facilityId,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facilityId: string;
  onCreated: () => void;
}) {
  const [plans, setPlans] = useState<MembershipPlan[]>([]);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);

  const [name, setName] = useState("");
  const [planId, setPlanId] = useState("");
  const [facilitySportId, setFacilitySportId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [days, setDays] = useState<number[]>([]);
  const [startTime, setStartTime] = useState("18:00");
  const [endTime, setEndTime] = useState("19:00");
  const [capacity, setCapacity] = useState("6");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setName("");
    setPlanId("");
    setFacilitySportId("");
    setCourtId("");
    setDays([]);
    setStartTime("18:00");
    setEndTime("19:00");
    setCapacity("6");
    setError(null);
    Promise.all([
      getMembershipService().getFacilityPlans(facilityId, { activeOnly: true }),
      getSportsService().getFacilitySports(facilityId),
      getSportsService().getActiveSports(),
      getPlayingAreasService().getPlayingAreas(facilityId),
    ]).then(([p, fs, all, pa]) => {
      setPlans(p);
      setFacilitySports(fs.filter((f) => f.enabled));
      setSports(all);
      setAreas(pa.filter((a) => !a.archived && a.status === "ACTIVE" && a.bookingEnabled));
    });
  }, [open, facilityId]);

  const courtsForSport = areas.filter((a) => a.facilitySportId === facilitySportId);

  async function submit() {
    const cap = Number(capacity);
    if (name.trim().length < 2) return setError("Enter a session name.");
    if (!planId || !facilitySportId || !courtId) return setError("Select a plan, sport, and court.");
    if (days.length === 0) return setError("Select at least one day.");
    if (!Number.isInteger(cap) || cap <= 0) return setError("Enter a valid capacity.");
    if (endTime <= startTime) return setError("End time must be after start time.");
    setSaving(true);
    setError(null);
    try {
      await getMembershipSessionService().createBatch({
        facilityId,
        planId,
        facilitySportId,
        courtId,
        name: name.trim(),
        daysOfWeek: days,
        startTime,
        endTime,
        capacity: cap,
      });
      onCreated();
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ServiceError ? err.message : "Unable to create this session.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Create Session</DialogTitle>
          <DialogDescription>A recurring session that reserves court capacity for a membership plan.</DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label>Session name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Evening Badminton" />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1.5">
              <Label>Plan</Label>
              <select value={planId} onChange={(e) => setPlanId(e.target.value)} className={selectCls}>
                <option value="">Select plan</option>
                {plans.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-1.5">
              <Label>Sport</Label>
              <select
                value={facilitySportId}
                onChange={(e) => {
                  setFacilitySportId(e.target.value);
                  setCourtId("");
                }}
                className={selectCls}
              >
                <option value="">Select sport</option>
                {facilitySports.map((fs) => {
                  const s = sports.find((sp) => sp.id === fs.sportId);
                  return (
                    <option key={fs.id} value={fs.id}>
                      {fs.customSportName ?? s?.name ?? "Sport"}
                    </option>
                  );
                })}
              </select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Court</Label>
            <select
              value={courtId}
              onChange={(e) => setCourtId(e.target.value)}
              disabled={!facilitySportId}
              className={`${selectCls} disabled:opacity-50`}
            >
              <option value="">Select court</option>
              {courtsForSport.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-1.5">
            <Label>Days</Label>
            <div className="flex flex-wrap gap-2">
              {DAYS.map((d) => (
                <button
                  key={d.value}
                  type="button"
                  onClick={() => setDays((prev) => (prev.includes(d.value) ? prev.filter((x) => x !== d.value) : [...prev, d.value]))}
                  className={`h-8 rounded-md border px-2 text-xs font-medium ${
                    days.includes(d.value) ? "border-primary bg-primary text-primary-foreground" : "border-input bg-secondary/60"
                  }`}
                >
                  {d.label}
                </button>
              ))}
            </div>
          </div>
          <div className="grid grid-cols-3 gap-2">
            <div className="space-y-1.5">
              <Label>From</Label>
              <input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} className={selectCls} />
            </div>
            <div className="space-y-1.5">
              <Label>To</Label>
              <input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} className={selectCls} />
            </div>
            <div className="space-y-1.5">
              <Label>Capacity</Label>
              <Input value={capacity} onChange={(e) => setCapacity(e.target.value)} inputMode="numeric" />
            </div>
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button type="button" onClick={submit} disabled={saving}>
            {saving ? "Creating…" : "Create Session"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}