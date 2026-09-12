"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { rupeesToMinor } from "@/features/coaching/components/shared";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { PageHeader } from "@/features/coaching/components/shared";
import type { CoachCandidate, CoachStatus } from "@/features/coaching/types";

export function AddCoachPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;

  const [candidates, setCandidates] = useState<CoachCandidate[]>([]);
  const [userId, setUserId] = useState("");
  const [specialization, setSpecialization] = useState("");
  const [experience, setExperience] = useState("");
  const [certifications, setCertifications] = useState("");
  const [bio, setBio] = useState("");
  const [hourlyRate, setHourlyRate] = useState("");
  const [status, setStatus] = useState<CoachStatus>("ACTIVE");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService()
      .listCoachCandidates(facilityId)
      .then(setCandidates)
      .catch(() => setCandidates([]));
  }, [facilityId]);

  if (!perms?.can("COACHING_MANAGE_COACHES")) {
    return <PermissionDenied message="You don't have permission to manage coaches." />;
  }

  async function submit() {
    if (!facilityId) return;
    if (!userId) {
      setError("Select the staff member to make a coach.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const id = await getCoachingService().addCoach(facilityId, userId, {
        specialization: specialization.trim() || null,
        experienceYears: experience.trim() ? Number(experience) : null,
        certifications: certifications.trim() || null,
        bio: bio.trim() || null,
        hourlyRateMinor: hourlyRate.trim() ? rupeesToMinor(hourlyRate) : null,
        status,
      });
      router.push(`/coaching/coaches/${id}`);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not add the coach.");
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-xl space-y-4">
      <PageHeader title="Add Coach" subtitle="Give an existing staff member a coaching profile." />

      <Card className="space-y-4 p-5">
        <div className="space-y-1.5">
          <Label htmlFor="coach-user">Staff member</Label>
          <Select value={userId} onValueChange={setUserId}>
            <SelectTrigger id="coach-user">
              <SelectValue placeholder="Select a staff member" />
            </SelectTrigger>
            <SelectContent>
              {candidates.length === 0 ? (
                <SelectItem value="__none" disabled>
                  Every staff member is already a coach
                </SelectItem>
              ) : (
                candidates.map((c) => (
                  <SelectItem key={c.userId} value={c.userId}>
                    {c.fullName}
                    {c.title ? ` · ${c.title}` : ""}
                  </SelectItem>
                ))
              )}
            </SelectContent>
          </Select>
          <p className="text-xs text-muted-foreground">
            A coach must already be a staff member — this never creates a new account.
          </p>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="coach-spec">Specialization</Label>
          <Input id="coach-spec" value={specialization} onChange={(e) => setSpecialization(e.target.value)} placeholder="Beginner, Advanced, Kids…" />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label htmlFor="coach-exp">Experience (years)</Label>
            <Input id="coach-exp" type="number" min="0" step="0.5" value={experience} onChange={(e) => setExperience(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="coach-rate">Hourly rate (₹, optional)</Label>
            <Input id="coach-rate" type="number" min="0" step="1" value={hourlyRate} onChange={(e) => setHourlyRate(e.target.value)} />
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="coach-cert">Certifications</Label>
          <Input id="coach-cert" value={certifications} onChange={(e) => setCertifications(e.target.value)} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="coach-bio">Bio</Label>
          <Textarea id="coach-bio" rows={3} value={bio} onChange={(e) => setBio(e.target.value)} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="coach-status">Status</Label>
          <Select value={status} onValueChange={(v) => setStatus(v as CoachStatus)}>
            <SelectTrigger id="coach-status">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="ACTIVE">Active</SelectItem>
              <SelectItem value="ON_LEAVE">On Leave</SelectItem>
              <SelectItem value="INACTIVE">Inactive</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex items-center justify-between border-t border-border pt-4">
          <Button asChild variant="outline">
            <Link href="/coaching/coaches">Cancel</Link>
          </Button>
          <Button onClick={() => void submit()} disabled={busy}>
            {busy ? "Adding…" : "Add Coach"}
          </Button>
        </div>
      </Card>
    </div>
  );
}
