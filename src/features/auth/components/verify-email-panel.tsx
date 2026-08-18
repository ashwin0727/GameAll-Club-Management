"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { ExternalLink, MailCheck, RotateCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { TextField } from "@/features/auth/components/text-field";
import { FormMessage } from "@/features/auth/components/form-message";
import { usePendingSignup } from "@/features/auth/context/pending-signup";
import { useChangeEmail, useResendVerification } from "@/features/auth/hooks/use-auth";
import { changeEmailSchema, type ChangeEmailInput } from "@/features/auth/validation";
import { RESEND_COOLDOWN_SECONDS } from "@/lib/constants";

/** Deep link to the webmail most turf owners actually use, when we can tell. */
const WEBMAIL_BY_DOMAIN: Record<string, string> = {
  "gmail.com": "https://mail.google.com",
  "googlemail.com": "https://mail.google.com",
  "outlook.com": "https://outlook.live.com/mail",
  "hotmail.com": "https://outlook.live.com/mail",
  "live.com": "https://outlook.live.com/mail",
  "yahoo.com": "https://mail.yahoo.com",
  "yahoo.in": "https://mail.yahoo.com",
  "rediffmail.com": "https://mail.rediff.com",
  "zoho.com": "https://mail.zoho.com",
  "proton.me": "https://mail.proton.me",
};

function inboxUrl(email: string): string | null {
  const domain = email.split("@")[1]?.toLowerCase();
  return domain ? (WEBMAIL_BY_DOMAIN[domain] ?? null) : null;
}

/** Counts down the resend cooldown, so a stuck user cannot hammer the mailer. */
function useCooldown(seconds: number) {
  const [remaining, setRemaining] = React.useState(0);

  React.useEffect(() => {
    if (remaining <= 0) return;
    const timer = window.setTimeout(() => setRemaining((value) => value - 1), 1000);
    return () => window.clearTimeout(timer);
  }, [remaining]);

  return { remaining, start: () => setRemaining(seconds) };
}

export function VerifyEmailPanel() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const { pending, setPending } = usePendingSignup();
  const email = pending?.email ?? searchParams.get("email") ?? "";

  const [editingEmail, setEditingEmail] = React.useState(false);
  const resend = useResendVerification();
  const changeEmail = useChangeEmail();
  const cooldown = useCooldown(RESEND_COOLDOWN_SECONDS);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<ChangeEmailInput>({
    resolver: zodResolver(changeEmailSchema),
    mode: "onTouched",
    defaultValues: { email: "" },
  });

  // Landing here with no address at all (direct URL, cleared state) means we
  // have nothing to verify — send them back to the start of the flow.
  if (!email) {
    return (
      <div className="space-y-6">
        <FormMessage tone="info">
          We don&apos;t have an address to verify. Create your account to get a confirmation link.
        </FormMessage>
        <Button asChild className="h-11 w-full">
          <Link href="/signup">Create Account</Link>
        </Button>
      </div>
    );
  }

  const onResend = () => {
    if (cooldown.remaining > 0) return;
    resend.mutate(email, { onSuccess: () => cooldown.start() });
  };

  const onChangeEmail = (values: ChangeEmailInput) => {
    // Re-issuing the signup needs the password, which only survives in memory.
    // After a reload it is gone, so the correction restarts at signup.
    if (!pending) {
      router.push(`/signup?email=${encodeURIComponent(values.email)}`);
      return;
    }

    changeEmail.mutate(
      { email: values.email, name: pending.name, password: pending.password },
      {
        onSuccess: () => {
          setPending({ ...pending, email: values.email });
          setEditingEmail(false);
          cooldown.start();
        },
      },
    );
  };

  const webmail = inboxUrl(email);

  if (editingEmail) {
    return (
      <form onSubmit={handleSubmit(onChangeEmail)} className="space-y-5" noValidate>
        {changeEmail.isError && <FormMessage>{changeEmail.error.message}</FormMessage>}

        <div className="rounded-lg border border-border bg-secondary/60 px-3.5 py-3 text-sm">
          <p className="text-muted-foreground">Current email</p>
          <p className="mt-0.5 font-medium">{email}</p>
        </div>

        <TextField
          id="change-email"
          label="New email address"
          type="email"
          inputMode="email"
          autoComplete="email"
          enterKeyHint="go"
          placeholder="owner@yourturf.com"
          error={errors.email?.message}
          {...register("email")}
        />

        <SubmitButton pending={changeEmail.isPending} pendingLabel="Updating…">
          Update Email
        </SubmitButton>

        <Button
          type="button"
          variant="ghost"
          className="h-11 w-full"
          onClick={() => setEditingEmail(false)}
        >
          Cancel
        </Button>
      </form>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start gap-3 rounded-xl border border-border bg-secondary/60 p-4">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary/10">
          <MailCheck className="h-5 w-5 text-primary" aria-hidden="true" />
        </div>
        <div className="min-w-0 space-y-1">
          <p className="text-sm text-muted-foreground">We&apos;ve sent a verification link to</p>
          <p className="break-words text-sm font-semibold text-foreground">{email}</p>
        </div>
      </div>

      <p className="text-sm leading-relaxed text-muted-foreground">
        Please check your inbox and click the verification link to continue. If it isn&apos;t there
        within a minute, check your spam folder.
      </p>

      {resend.isError && <FormMessage>{resend.error.message}</FormMessage>}
      {resend.isSuccess && !resend.isError && cooldown.remaining > 0 && (
        <FormMessage tone="success">Verification email sent again.</FormMessage>
      )}

      <div className="space-y-3">
        {webmail && (
          <Button asChild className="h-11 w-full">
            <a href={webmail} target="_blank" rel="noopener noreferrer">
              Open Email
              <ExternalLink className="h-4 w-4" aria-hidden="true" />
            </a>
          </Button>
        )}

        <Button
          type="button"
          variant="outline"
          className="h-11 w-full"
          onClick={onResend}
          disabled={cooldown.remaining > 0 || resend.isPending}
          aria-busy={resend.isPending || undefined}
        >
          <RotateCw
            className={resend.isPending ? "h-4 w-4 animate-spin" : "h-4 w-4"}
            aria-hidden="true"
          />
          {cooldown.remaining > 0
            ? `Resend available in ${cooldown.remaining}s`
            : "Resend Verification Email"}
        </Button>

        <Button
          type="button"
          variant="ghost"
          className="h-11 w-full"
          onClick={() => setEditingEmail(true)}
        >
          Change Email
        </Button>
      </div>

      <div className="border-t border-border pt-5 text-center text-sm text-muted-foreground">
        Already verified?{" "}
        <Link
          href={`/login?email=${encodeURIComponent(email)}`}
          className="rounded font-medium text-primary underline-offset-4 outline-none hover:underline focus-visible:ring-2 focus-visible:ring-ring"
        >
          Continue to Sign In
        </Link>
      </div>
    </div>
  );
}