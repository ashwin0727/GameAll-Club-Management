"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { passwordSchema } from "@/features/auth/validation";
import { profileKeys, useNotificationPrefs } from "@/features/profile/hooks";
import { PageMessage, SectionCard, SubPageHeader } from "@/features/profile/components/profile-shared";
import { DEFAULT_NOTIFICATION_PREFS } from "@/features/profile/plan";
import type { NotificationPrefs } from "@/features/profile/types";
import { getAuthService } from "@/services/auth";
import { getProfileService } from "@/services/profile";
import { cn } from "@/lib/utils";

const PREF_ROWS: { key: keyof NotificationPrefs; title: string; description: string }[] = [
  { key: "bookings", title: "Bookings", description: "New, changed and cancelled bookings." },
  { key: "payments", title: "Payments", description: "Payments received, refunds and anything still pending." },
  { key: "memberships", title: "Memberships", description: "New memberships, renewals and ones about to end." },
  { key: "reports", title: "Weekly summary", description: "A weekly recap of bookings and revenue." },
];

function Toggle({ checked, onChange, label, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cn(
        "relative h-6 w-11 shrink-0 rounded-full transition-colors outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-60",
        checked ? "bg-primary" : "bg-muted-foreground/30",
      )}
    >
      <span
        aria-hidden
        className={cn("absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform", checked ? "translate-x-[22px]" : "translate-x-0.5")}
      />
    </button>
  );
}

function NotificationsCard() {
  const qc = useQueryClient();
  const prefs = useNotificationPrefs();
  const [error, setError] = useState<string | null>(null);

  const save = useMutation({
    mutationFn: (next: NotificationPrefs) => getProfileService().saveNotificationPrefs(next),
    onMutate: async (next) => {
      setError(null);
      await qc.cancelQueries({ queryKey: profileKeys.prefs });
      const previous = qc.getQueryData<NotificationPrefs>(profileKeys.prefs);
      qc.setQueryData(profileKeys.prefs, next);
      return { previous };
    },
    onError: (e, _next, ctx) => {
      if (ctx?.previous) qc.setQueryData(profileKeys.prefs, ctx.previous);
      setError(e instanceof Error ? e.message : "Could not save your settings.");
    },
  });

  const current = prefs.data ?? DEFAULT_NOTIFICATION_PREFS;

  return (
    <SectionCard title="Notifications" description="Choose what you want to hear about. Changes save as you make them.">
      {prefs.isLoading ? (
        <Skeleton className="h-40 w-full rounded-lg" />
      ) : prefs.isError ? (
        <PageMessage tone="error">Unable to load your settings. Please try again.</PageMessage>
      ) : (
        <ul className="divide-y divide-border">
          {PREF_ROWS.map((row) => (
            <li key={row.key} className="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0">
              <div className="min-w-0">
                <p className="text-sm font-medium">{row.title}</p>
                <p className="text-xs text-muted-foreground">{row.description}</p>
              </div>
              <Toggle
                label={row.title}
                checked={current[row.key]}
                onChange={(v) => save.mutate({ ...current, [row.key]: v })}
              />
            </li>
          ))}
        </ul>
      )}
      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}
    </SectionCard>
  );
}

function PasswordCard() {
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [done, setDone] = useState(false);

  const change = useMutation({
    mutationFn: (value: string) => getAuthService().updatePassword(value),
    onSuccess: () => {
      setPassword("");
      setConfirm("");
      setErrors({});
      setDone(true);
    },
    onError: (e) => setErrors({ form: e instanceof Error ? e.message : "Could not change your password." }),
  });

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setDone(false);
    const parsed = passwordSchema.safeParse(password);
    if (!parsed.success) return setErrors({ password: parsed.error.issues[0]?.message ?? "Enter a stronger password." });
    if (password !== confirm) return setErrors({ confirm: "Passwords do not match." });
    setErrors({});
    change.mutate(password);
  }

  return (
    <SectionCard title="Change password" description="Use a password you don't use anywhere else.">
      <form onSubmit={submit} className="grid gap-4 sm:max-w-md" noValidate>
        <div className="space-y-1.5">
          <Label htmlFor="new-password">New password</Label>
          <Input id="new-password" type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} />
          {errors.password && <p className="text-xs text-destructive">{errors.password}</p>}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="confirm-password">Confirm new password</Label>
          <Input id="confirm-password" type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />
          {errors.confirm && <p className="text-xs text-destructive">{errors.confirm}</p>}
        </div>
        {errors.form && (
          <p role="alert" className="text-sm text-destructive">
            {errors.form}
          </p>
        )}
        {done && (
          <p role="status" className="rounded-lg bg-success/10 px-3 py-2 text-sm text-success">
            Your password has been changed.
          </p>
        )}
        <div>
          <Button type="submit" disabled={change.isPending || password === ""}>
            {change.isPending ? "Updating…" : "Update password"}
          </Button>
        </div>
      </form>
    </SectionCard>
  );
}

/** Settings: notification preferences and password. */
export function SettingsPage() {
  return (
    <div className="space-y-4">
      <SubPageHeader title="Settings" description="Your notification preferences and account security." />
      <NotificationsCard />
      <PasswordCard />
    </div>
  );
}
