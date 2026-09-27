"use client";

import { useRef, type WheelEvent } from "react";
import { Camera } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Chip, initials } from "@/features/coaching/components/shared";
import { AVATAR_ACCEPT, DURATION_OPTIONS, type AddCoachFormState } from "@/features/coaching/components/use-add-coach-form";
import { dateOfBirthBounds, isValidDateOfBirth, isValidEmail, isValidPhoneDigits } from "@/features/coaching/add-coach-validation";
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { COACH_EXPERTISE_LEVELS, type CoachStatus } from "@/features/coaching/types";
import { cn } from "@/lib/utils";

/** No spinner arrows — a coach's years of experience isn't the kind of value anyone increments
 *  one click at a time, and the arrows just take up space next to the digits. */
const NO_SPINNER_INPUT = "[appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none";

/** Browsers change a focused number input's value on mouse-wheel scroll regardless of whether
 *  the spinner arrows are hidden — blurring on wheel is the standard, reliable way to stop that
 *  (an onWheel `preventDefault` doesn't work here since React/the browser treats wheel listeners
 *  as passive by default). */
function blurOnWheel(e: WheelEvent<HTMLInputElement>) {
  e.currentTarget.blur();
}

function SectionHeading({ n, title, subtitle }: { n: number; title: string; subtitle: string }) {
  return (
    <div className="flex items-start gap-3">
      <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-success/15 text-sm font-semibold text-success">
        {n}
      </span>
      <div>
        <h3 className="text-sm font-semibold">{title}</h3>
        <p className="text-xs text-muted-foreground">{subtitle}</p>
      </div>
    </div>
  );
}

/**
 * The three numbered sections (Basic Information / Coaching Details / Availability & Settings) —
 * pure fields, no header and no Cancel/Submit footer, so the full-page route and the slide-over
 * sheet can each wrap this in whatever chrome fits their own layout.
 */
export function AddCoachFormFields({ facilityId, form }: { facilityId: string | null; form: AddCoachFormState }) {
  const sportsQuery = useFacilitySportOptions(facilityId ?? undefined);
  const avatarInputRef = useRef<HTMLInputElement>(null);

  return (
    <div className="space-y-6">
      {/* ── 1. Basic Information ─────────────────────────────────────── */}
      <section className="space-y-3">
        <SectionHeading n={1} title="Basic Information" subtitle="Enter the coach's personal and contact details." />

        <div className="flex gap-2">
          <Button type="button" size="sm" variant={form.mode === "pick" ? "default" : "outline"} onClick={() => form.setMode("pick")}>
            Existing staff member
          </Button>
          <Button type="button" size="sm" variant={form.mode === "new" ? "default" : "outline"} onClick={() => form.setMode("new")}>
            + New person
          </Button>
        </div>

        {form.mode === "pick" ? (
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label htmlFor="coach-user">Staff member</Label>
              <Select value={form.userId} onValueChange={form.setUserId}>
                <SelectTrigger id="coach-user">
                  <SelectValue placeholder="Select a staff member" />
                </SelectTrigger>
                <SelectContent>
                  {form.candidates.length === 0 ? (
                    <SelectItem value="__none" disabled>
                      Every staff member is already a coach
                    </SelectItem>
                  ) : (
                    form.candidates.map((c) => (
                      <SelectItem key={c.userId} value={c.userId}>
                        {c.fullName}
                        {c.title ? ` · ${c.title}` : ""}
                      </SelectItem>
                    ))
                  )}
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                Not on the list yet? Use &ldquo;+ New person&rdquo; above to add them as staff first.
              </p>
            </div>
            {form.selectedCandidate && (
              <div className="flex items-center gap-3 rounded-lg border border-border bg-muted/30 p-3">
                <Avatar className="h-10 w-10">
                  {form.selectedCandidate.avatarUrl && <AvatarImage src={form.selectedCandidate.avatarUrl} alt="" />}
                  <AvatarFallback>{initials(form.selectedCandidate.fullName)}</AvatarFallback>
                </Avatar>
                <div className="min-w-0 text-sm">
                  <p className="truncate font-medium">{form.selectedCandidate.fullName}</p>
                  <p className="truncate text-muted-foreground">
                    {[form.selectedCandidate.phone, form.selectedCandidate.email].filter(Boolean).join(" · ") || "No contact details on file"}
                  </p>
                </div>
              </div>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div className="space-y-1.5 sm:col-span-2">
              <Label>Profile Photo</Label>
              <div className="flex items-center gap-3">
                <Avatar className="h-14 w-14">
                  {form.avatarPreview && <AvatarImage src={form.avatarPreview} alt="" />}
                  <AvatarFallback>
                    <Camera className="h-5 w-5 text-muted-foreground" aria-hidden />
                  </AvatarFallback>
                </Avatar>
                <div>
                  <input
                    ref={avatarInputRef}
                    type="file"
                    accept={AVATAR_ACCEPT.join(",")}
                    className="hidden"
                    onChange={(e) => form.pickAvatar(e.target.files?.[0])}
                  />
                  <Button type="button" size="sm" variant="outline" onClick={() => avatarInputRef.current?.click()}>
                    Upload Photo
                  </Button>
                  <p className="mt-1 text-xs text-muted-foreground">JPG, PNG (Max 2MB)</p>
                  {form.avatarError && <p className="mt-1 text-xs text-destructive">{form.avatarError}</p>}
                </div>
              </div>
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="np-name">Full Name *</Label>
              <Input
                id="np-name"
                value={form.newPerson.fullName}
                onChange={(e) => form.setNewPerson((p) => ({ ...p, fullName: e.target.value }))}
                placeholder="Enter full name"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="np-phone">Phone Number</Label>
              <Input
                id="np-phone"
                type="tel"
                inputMode="numeric"
                maxLength={10}
                value={form.newPerson.phone}
                onChange={(e) => form.setPhone(e.target.value)}
                placeholder="98765 43210"
              />
              {!isValidPhoneDigits(form.newPerson.phone) && (
                <p className="text-xs text-destructive">Enter all 10 digits of the phone number.</p>
              )}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="np-email">Email *</Label>
              <Input
                id="np-email"
                type="email"
                value={form.newPerson.email}
                onChange={(e) => form.setNewPerson((p) => ({ ...p, email: e.target.value }))}
                placeholder="Enter email address"
              />
              {form.newPerson.email.length > 0 && !isValidEmail(form.newPerson.email) && (
                <p className="text-xs text-destructive">Enter a valid email address.</p>
              )}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="np-dob">Date of Birth (Optional)</Label>
              <Input
                id="np-dob"
                type="date"
                min={dateOfBirthBounds().min}
                max={dateOfBirthBounds().max}
                value={form.newPerson.dateOfBirth}
                onChange={(e) => form.setNewPerson((p) => ({ ...p, dateOfBirth: e.target.value }))}
              />
              {!isValidDateOfBirth(form.newPerson.dateOfBirth) && (
                <p className="text-xs text-destructive">Enter a valid date of birth (must be 18–100 years ago).</p>
              )}
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="np-role">Role *</Label>
              <Select value={form.newPerson.roleId} onValueChange={(v) => form.setNewPerson((p) => ({ ...p, roleId: v }))}>
                <SelectTrigger id="np-role">
                  <SelectValue placeholder="Select a role" />
                </SelectTrigger>
                <SelectContent>
                  {form.roles.length === 0 ? (
                    <SelectItem value="__none" disabled>
                      {form.rolesError ? "Unable to load roles" : "No roles available"}
                    </SelectItem>
                  ) : (
                    form.roles.map((r) => (
                      <SelectItem key={r.id} value={r.id}>
                        {r.name}
                      </SelectItem>
                    ))
                  )}
                </SelectContent>
              </Select>
              {form.rolesError && <p className="mt-1 text-xs text-destructive">{form.rolesError}</p>}
            </div>
            <p className="text-xs text-muted-foreground sm:col-span-2">
              This creates a new staff account for this person — coaches are always staff members.
            </p>
          </div>
        )}
      </section>

      <div className="border-t border-border" />

      {/* ── 2. Coaching Details ──────────────────────────────────────── */}
      <section className="space-y-3">
        <SectionHeading n={2} title="Coaching Details" subtitle="Select the sports, expertise and experience." />

        <div className="space-y-1.5">
          <Label>Sports *</Label>
          <div className="flex flex-wrap gap-2">
            {(sportsQuery.data ?? []).map((s) => (
              <Chip
                key={s.facilitySportId}
                label={s.name}
                selected={form.sportIds.includes(s.facilitySportId)}
                onToggle={() => form.toggle(form.sportIds, form.setSportIds, s.facilitySportId)}
              />
            ))}
          </div>
        </div>

        <div className="space-y-1.5">
          <Label>Expertise Level *</Label>
          <div className="flex flex-wrap gap-2">
            {COACH_EXPERTISE_LEVELS.map((level) => (
              <Chip
                key={level}
                label={level}
                selected={form.expertiseLevels.includes(level)}
                onToggle={() => form.toggle(form.expertiseLevels, form.setExpertiseLevels, level)}
              />
            ))}
          </div>
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="coach-exp">Years of Experience</Label>
            <Input
              id="coach-exp"
              type="number"
              min="0"
              step="0.5"
              value={form.experience}
              onChange={(e) => form.setExperience(e.target.value)}
              onWheel={blurOnWheel}
              className={NO_SPINNER_INPUT}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="coach-cert">Certification (Optional)</Label>
            <Input
              id="coach-cert"
              value={form.certifications}
              onChange={(e) => form.setCertifications(e.target.value)}
              placeholder="e.g. BWF Level 1, Certified Coach"
            />
          </div>
        </div>
      </section>

      <div className="border-t border-border" />

      {/* ── 3. Availability & Settings ───────────────────────────────── */}
      <section className="space-y-3">
        <SectionHeading n={3} title="Availability & Settings" subtitle="Set the coach's availability and status." />
        <p className="text-xs text-muted-foreground">
          The weekly recurring schedule is set up next, from the coach&apos;s profile — this just covers status and defaults.
        </p>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="coach-status">Status</Label>
            <Select value={form.status} onValueChange={(v) => form.setStatus(v as CoachStatus)}>
              <SelectTrigger id="coach-status">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="ACTIVE">Active</SelectItem>
                <SelectItem value="INACTIVE">Inactive</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="coach-duration">Default Session Duration</Label>
            <Select value={form.duration} onValueChange={form.setDuration}>
              <SelectTrigger id="coach-duration">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {DURATION_OPTIONS.map((d) => (
                  <SelectItem key={d.value} value={d.value}>
                    {d.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {form.duration === "custom" && (
              <div className="flex items-center gap-2">
                <Input
                  type="number"
                  min="1"
                  step="1"
                  aria-label="Custom duration in minutes"
                  placeholder="e.g. 75"
                  value={form.customDuration}
                  onChange={(e) => form.setCustomDuration(e.target.value)}
                  onWheel={blurOnWheel}
                  className={cn("w-28", NO_SPINNER_INPUT)}
                />
                <span className="text-sm text-muted-foreground">minutes</span>
              </div>
            )}
          </div>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="coach-bio">Coach Bio (Optional)</Label>
          <Textarea
            id="coach-bio"
            rows={3}
            maxLength={500}
            value={form.bio}
            onChange={(e) => form.setBio(e.target.value)}
            placeholder="Write a short bio about the coach, their achievements and coaching style…"
          />
          <p className="text-right text-xs text-muted-foreground">{form.bio.length}/500</p>
        </div>
      </section>

      {form.error && <p className="text-sm text-destructive">{form.error}</p>}
    </div>
  );
}

export function submitButtonLabel(form: AddCoachFormState): string {
  return form.uploadingPhoto ? "Uploading photo…" : form.creatingStaff ? "Creating staff account…" : form.busy ? "Adding…" : "+ Add Coach";
}
