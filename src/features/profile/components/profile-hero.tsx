"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { BadgeCheck, Camera, Loader2, Mail, Pencil, Phone } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { useFacility } from "@/features/facility/hooks/use-facility";
import type { Profile } from "@/features/auth/types";
import { ACCEPTED_LOGO_TYPES } from "@/features/onboarding/constants";
import { formatPhone, normalisePhone, profileEditSchema } from "@/features/profile/profile-validation";
import { getProfileService } from "@/services/profile";
import { cn, getInitials } from "@/lib/utils";

const MAX_AVATAR_BYTES = 2 * 1024 * 1024;

const ROLE_TITLE: Record<Profile["role"], string> = { admin: "Facility Owner", staff: "Facility Staff", member: "Member" };

/** The profile photo with a camera button that uploads a new one straight away. */
export function ProfileAvatar({ profile, size = "lg" }: { profile: Profile; size?: "lg" | "md" }) {
  const router = useRouter();
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onFile(file: File | undefined) {
    if (!file) return;
    if (!ACCEPTED_LOGO_TYPES.includes(file.type)) return setError("Use a PNG, JPG or WebP image.");
    if (file.size > MAX_AVATAR_BYTES) return setError("Photos must be smaller than 2MB.");
    setError(null);
    setBusy(true);
    try {
      const url = await getProfileService().uploadAvatar(file);
      await getProfileService().updateProfile({ fullName: profile.full_name, phone: profile.phone, avatarUrl: url });
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not upload this photo.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="relative shrink-0">
      <Avatar className={cn("border-4 border-white shadow-md", size === "lg" ? "h-24 w-24 sm:h-28 sm:w-28" : "h-16 w-16")}>
        {profile.avatar_url && <AvatarImage src={profile.avatar_url} alt="" className="object-cover" />}
        <AvatarFallback className="bg-primary text-2xl font-semibold text-primary-foreground">
          {getInitials(profile.full_name)}
        </AvatarFallback>
      </Avatar>
      <input
        ref={input}
        type="file"
        accept={ACCEPTED_LOGO_TYPES.join(",")}
        className="sr-only"
        aria-label="Upload a profile photo"
        onChange={(e) => {
          void onFile(e.target.files?.[0]);
          e.target.value = "";
        }}
      />
      <button
        type="button"
        onClick={() => input.current?.click()}
        disabled={busy}
        aria-label="Change profile photo"
        className="absolute bottom-0 right-0 flex h-8 w-8 items-center justify-center rounded-full border-2 border-white bg-slate-800 text-white shadow transition-transform hover:scale-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-70"
      >
        {busy ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : <Camera className="h-4 w-4" aria-hidden />}
      </button>
      {error && (
        <p role="alert" className="absolute left-0 top-full z-10 mt-1 w-48 text-xs text-destructive">
          {error}
        </p>
      )}
    </div>
  );
}

function EditProfileDialog({
  profile,
  fallbackPhone,
  open,
  onClose,
}: {
  profile: Profile;
  fallbackPhone: string | null;
  open: boolean;
  onClose: () => void;
}) {
  const router = useRouter();
  const [fullName, setFullName] = useState(profile.full_name);
  const [phone, setPhone] = useState(normalisePhone(profile.phone || fallbackPhone || ""));
  const [errors, setErrors] = useState<Partial<Record<"fullName" | "phone" | "form", string>>>({});
  const [saving, setSaving] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const parsed = profileEditSchema.safeParse({ fullName, phone });
    if (!parsed.success) {
      const next: typeof errors = {};
      for (const issue of parsed.error.issues) next[issue.path[0] as "fullName" | "phone"] ??= issue.message;
      return setErrors(next);
    }
    setErrors({});
    setSaving(true);
    try {
      await getProfileService().updateProfile({
        fullName: parsed.data.fullName,
        phone: parsed.data.phone === "" ? null : normalisePhone(parsed.data.phone),
      });
      router.refresh();
      onClose();
    } catch (err) {
      setErrors({ form: err instanceof Error ? err.message : "Could not save your profile." });
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !o && !saving && onClose()}>
      <DialogContent className="max-w-md">
        <form onSubmit={save} className="space-y-4" noValidate>
          <DialogHeader>
            <DialogTitle>Edit profile</DialogTitle>
            <DialogDescription>Your email is your sign-in, so it can&apos;t be changed here.</DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label htmlFor="profile-name">Full name</Label>
            <Input id="profile-name" value={fullName} onChange={(e) => setFullName(e.target.value)} autoComplete="name" />
            {errors.fullName && <p className="text-xs text-destructive">{errors.fullName}</p>}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="profile-phone">Mobile number</Label>
            <Input
              id="profile-phone"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              inputMode="tel"
              autoComplete="tel"
              placeholder="98765 43210"
            />
            {errors.phone && <p className="text-xs text-destructive">{errors.phone}</p>}
          </div>
          {errors.form && <p role="alert" className="text-sm text-destructive">{errors.form}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose} disabled={saving}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving}>
              {saving ? "Saving…" : "Save changes"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/**
 * The banner at the top of the profile: photo, name, verified badge, role, mobile and email, laid over the profile
 * artwork (/assets/Banner_Profile.png). The artwork is light in its middle and dark green/blue in its corners, in both
 * themes, so the text on it is fixed dark rather than following the theme.
 */
export function ProfileHero({ profile }: { profile: Profile }) {
  const { data: user } = useCurrentUser();
  const { data: facility } = useFacility();
  const [editing, setEditing] = useState(false);
  // Until a personal number is added, the facility's own contact number stands in for it.
  const mobile = profile.phone || facility?.businessPhone || null;
  const verified = user?.emailVerified ?? true;

  return (
    <section
      aria-label="Your profile"
      className="relative overflow-hidden rounded-xl border border-border bg-sky-50 bg-cover bg-center bg-no-repeat shadow-sm"
      style={{ backgroundImage: "url(/assets/Banner_Profile.png)" }}
    >
      {/* Once a photo is uploaded it also fills the right of the banner: a green chevron band, then the photo,
          both notched into an arrow shape like the design. */}
      {profile.avatar_url && (
        <div aria-hidden className="absolute inset-y-0 right-0 hidden w-[44%] sm:block">
          {/* Outer, pale chevron */}
          <div
            className="absolute inset-0 bg-gradient-to-b from-white/70 via-sky-100/60 to-emerald-100/70"
            style={{ clipPath: "polygon(0 0, 100% 0, 100% 100%, 0 100%, 26% 50%)" }}
          />
          {/* Green chevron band */}
          <div
            className="absolute inset-0 bg-gradient-to-b from-emerald-300 via-emerald-500 to-emerald-600"
            style={{ clipPath: "polygon(12% 0, 100% 0, 100% 100%, 12% 100%, 38% 50%)" }}
          />
          {/* The photo */}
          <div className="absolute inset-0" style={{ clipPath: "polygon(15.5% 0, 100% 0, 100% 100%, 15.5% 100%, 41.5% 50%)" }}>
            {/* eslint-disable-next-line @next/next/no-img-element -- user-uploaded photo from storage */}
            <img src={profile.avatar_url} alt="" className="h-full w-full object-cover" />
          </div>
        </div>
      )}
      <div
        className={cn(
          "relative flex flex-col items-center gap-4 px-5 pb-7 pt-14 text-center sm:flex-row sm:items-center sm:gap-6 sm:px-[9%] sm:py-9 sm:text-left",
          profile.avatar_url && "sm:pr-[46%]",
        )}
      >
        <ProfileAvatar profile={profile} />
        <div className="min-w-0 flex-1 space-y-1.5 text-slate-800">
          <div className="flex flex-wrap items-center justify-center gap-2 sm:justify-start">
            <h2 className="truncate text-xl font-semibold sm:text-2xl">{profile.full_name}</h2>
            {verified ? (
              <Badge className="gap-1 border-transparent bg-emerald-500/15 text-emerald-700 hover:bg-emerald-500/15">
                <BadgeCheck className="h-3.5 w-3.5" aria-hidden /> Verified User
              </Badge>
            ) : (
              <Badge className="border-transparent bg-amber-400/25 text-amber-800 hover:bg-amber-400/25">Email not verified</Badge>
            )}
          </div>
          <p className="text-sm text-slate-600">{ROLE_TITLE[profile.role]}</p>
          <div className="flex flex-col items-center gap-1 text-sm sm:items-start">
            <span className="flex items-center gap-2">
              <Phone className="h-4 w-4 shrink-0 text-slate-500" aria-hidden />
              {mobile ? formatPhone(mobile) : <span className="text-slate-500">Add your mobile number</span>}
            </span>
            <span className="flex min-w-0 items-center gap-2">
              <Mail className="h-4 w-4 shrink-0 text-slate-500" aria-hidden />
              <span className="truncate">{profile.email}</span>
            </span>
          </div>
        </div>
      </div>

      <Button
        type="button"
        size="sm"
        variant="outline"
        className="absolute right-3 top-3 z-10 border-white/70 bg-white/90 text-slate-800 shadow-sm backdrop-blur hover:bg-white"
        onClick={() => setEditing(true)}
      >
        <Pencil className="mr-1.5 h-3.5 w-3.5" aria-hidden /> Edit Profile
      </Button>

      {editing && <EditProfileDialog profile={profile} fallbackPhone={facility?.businessPhone ?? null} open onClose={() => setEditing(false)} />}
    </section>
  );
}
