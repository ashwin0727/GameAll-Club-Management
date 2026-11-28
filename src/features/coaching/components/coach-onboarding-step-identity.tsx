"use client";

import { useRef } from "react";
import { Camera } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Chip, initials } from "@/features/coaching/components/shared";
import { LANGUAGE_OPTIONS, OnboardingField, TIMEZONE_OPTIONS } from "@/features/coaching/components/coach-onboarding-field";
import { AVATAR_ACCEPT, type CoachOnboardingState } from "@/features/coaching/components/use-coach-onboarding";
import { dateOfBirthBounds, isValidDateOfBirth, isValidEmail, isValidPhoneDigits } from "@/features/coaching/add-coach-validation";

/** Step 1 — Identity & Basic Profile. */
export function IdentityStep({ form }: { form: CoachOnboardingState }) {
  const { draft, coachId } = form;
  const fileRef = useRef<HTMLInputElement>(null);
  const np = draft.newPerson;
  const selected = form.candidates.find((c) => c.userId === draft.userId) ?? null;
  const chooseWho = !coachId; // once the draft exists the person is fixed

  return (
    <div className="space-y-5">
      {!chooseWho && (
        <p className="rounded-lg border border-border bg-muted/30 p-3 text-sm text-muted-foreground">
          This draft is for <span className="font-medium text-foreground">{draft.displayName || "this coach"}</span>. The staff account is fixed once the draft is created; you can still change the profile details below.
        </p>
      )}
      {chooseWho && (
        <section className="space-y-3">
          <div className="flex gap-2">
            <Button type="button" size="sm" variant={draft.mode === "pick" ? "default" : "outline"} onClick={() => form.patch({ mode: "pick" })}>
              Existing Staff Member
            </Button>
            <Button type="button" size="sm" variant={draft.mode === "new" ? "default" : "outline"} onClick={() => form.patch({ mode: "new" })}>
              + New person
            </Button>
          </div>

          {draft.mode === "pick" ? (
            <div className="space-y-3">
              <OnboardingField label="Staff Member" required htmlFor="ob-staff" hint="Not on the list yet? Use “+ New person” above to add them as staff first.">
                <Select value={draft.userId} onValueChange={form.pickStaff}>
                  <SelectTrigger id="ob-staff">
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
              </OnboardingField>
              {selected && (
                <div className="flex items-center gap-3 rounded-lg border border-border bg-muted/30 p-3">
                  <Avatar className="h-10 w-10">
                    {selected.avatarUrl && <AvatarImage src={selected.avatarUrl} alt="" />}
                    <AvatarFallback>{initials(selected.fullName)}</AvatarFallback>
                  </Avatar>
                  <div className="min-w-0 text-sm">
                    <p className="truncate font-medium">{selected.fullName}</p>
                    <p className="truncate text-muted-foreground">{[selected.phone, selected.email].filter(Boolean).join(" · ") || "No contact details on file"}</p>
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <OnboardingField label="Profile Photo" className="sm:col-span-2" error={form.avatarError}>
                <div className="flex items-center gap-3">
                  <Avatar className="h-14 w-14">
                    {form.avatarPreview && <AvatarImage src={form.avatarPreview} alt="" />}
                    <AvatarFallback>
                      <Camera className="h-5 w-5 text-muted-foreground" aria-hidden />
                    </AvatarFallback>
                  </Avatar>
                  <div>
                    <input ref={fileRef} type="file" accept={AVATAR_ACCEPT.join(",")} className="hidden" onChange={(e) => form.pickAvatar(e.target.files?.[0])} />
                    <Button type="button" size="sm" variant="outline" onClick={() => fileRef.current?.click()}>
                      Upload Photo
                    </Button>
                    <p className="mt-1 text-xs text-muted-foreground">JPG, PNG or WEBP (max 2MB)</p>
                  </div>
                </div>
              </OnboardingField>
              <OnboardingField label="First Name" required htmlFor="ob-first">
                <Input
                  id="ob-first"
                  value={np.firstName}
                  onChange={(e) => {
                    form.patchNewPerson({ firstName: e.target.value });
                    // The display name is the whole first name until the owner types their own.
                    if (!draft.displayName || draft.displayName === np.firstName) form.patch({ displayName: e.target.value });
                  }}
                  placeholder="Legal first name"
                />
              </OnboardingField>
              <OnboardingField label="Last Name" required htmlFor="ob-last">
                <Input id="ob-last" value={np.lastName} onChange={(e) => form.patchNewPerson({ lastName: e.target.value })} placeholder="Legal last name" />
              </OnboardingField>
              <OnboardingField label="Phone Number" required htmlFor="ob-phone" error={!isValidPhoneDigits(np.phone) ? "Enter all 10 digits of the phone number." : null}>
                <Input id="ob-phone" type="tel" inputMode="numeric" maxLength={10} value={np.phone} onChange={(e) => form.setPhone(e.target.value)} placeholder="98765 43210" />
              </OnboardingField>
              <OnboardingField label="Email" required htmlFor="ob-email" error={np.email.length > 0 && !isValidEmail(np.email) ? "Enter a valid email address." : null}>
                <Input id="ob-email" type="email" value={np.email} onChange={(e) => form.patchNewPerson({ email: e.target.value })} placeholder="name@example.com" />
              </OnboardingField>
              <OnboardingField label="Role" required htmlFor="ob-role" className="sm:col-span-2" error={form.rolesError} hint="This creates a new staff account for this person — coaches are always staff members.">
                <Select value={np.roleId} onValueChange={(v) => form.patchNewPerson({ roleId: v })}>
                  <SelectTrigger id="ob-role">
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
              </OnboardingField>
            </div>
          )}
        </section>
      )}

      <section className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <OnboardingField label="Display Name" required htmlFor="ob-display" hint="Shown to students and on schedules.">
          <Input id="ob-display" value={draft.displayName} onChange={(e) => form.patch({ displayName: e.target.value })} placeholder="e.g. Coach Ravi" />
        </OnboardingField>
        <OnboardingField label="Location" htmlFor="ob-location" hint="City the coach is based in.">
          <Input id="ob-location" value={draft.location} onChange={(e) => form.patch({ location: e.target.value })} placeholder="e.g. Chennai" />
        </OnboardingField>
        <OnboardingField label="Timezone" required htmlFor="ob-tz">
          <Select value={draft.timezone} onValueChange={(v) => form.patch({ timezone: v })}>
            <SelectTrigger id="ob-tz">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {TIMEZONE_OPTIONS.map((t) => (
                <SelectItem key={t.value} value={t.value}>
                  {t.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </OnboardingField>
        <OnboardingField
          label="Date of Birth (Optional)"
          htmlFor="ob-dob"
          error={!isValidDateOfBirth(draft.dateOfBirth) ? "Enter a valid date of birth (must be 18–100 years ago)." : null}
        >
          <Input id="ob-dob" type="date" min={dateOfBirthBounds().min} max={dateOfBirthBounds().max} value={draft.dateOfBirth} onChange={(e) => form.patch({ dateOfBirth: e.target.value })} />
        </OnboardingField>
        <OnboardingField label="Languages Spoken" className="sm:col-span-2">
          <div className="flex flex-wrap gap-2">
            {LANGUAGE_OPTIONS.map((l) => (
              <Chip key={l} label={l} selected={draft.languages.includes(l)} onToggle={() => form.patch({ languages: form.toggle(draft.languages, l) })} />
            ))}
          </div>
        </OnboardingField>
        <OnboardingField label="Short Bio (Optional)" htmlFor="ob-bio" className="sm:col-span-2">
          <Textarea id="ob-bio" rows={3} maxLength={500} value={draft.shortBio} onChange={(e) => form.patch({ shortBio: e.target.value })} placeholder="A short introduction students will see…" />
          <p className="text-right text-xs text-muted-foreground">{draft.shortBio.length}/500</p>
        </OnboardingField>
      </section>
    </div>
  );
}
