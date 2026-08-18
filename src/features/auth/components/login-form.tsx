"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { TextField } from "@/features/auth/components/text-field";
import { PasswordInput } from "@/features/auth/components/password-input";
import { FormMessage } from "@/features/auth/components/form-message";
import { useLogin } from "@/features/auth/hooks/use-auth";
import { loginSchema, type LoginInput } from "@/features/auth/validation";
import { AuthError } from "@/services/auth";

export function LoginForm() {
  const login = useLogin();
  const searchParams = useSearchParams();
  const justVerified = searchParams.get("verified") === "1";

  const {
    register,
    handleSubmit,
    getValues,
    formState: { errors, isSubmitting },
  } = useForm<LoginInput>({
    resolver: zodResolver(loginSchema),
    mode: "onTouched",
    defaultValues: { email: searchParams.get("email") ?? "", password: "" },
  });

  const pending = login.isPending || isSubmitting;
  // An unverified account is the one failure with a next step attached, so it
  // gets a link rather than a dead-end message.
  const unverified = login.error instanceof AuthError && login.error.code === "email_not_verified";

  return (
    <form onSubmit={handleSubmit((values) => login.mutate(values))} className="space-y-5" noValidate>
      {justVerified && !login.isError && (
        <FormMessage tone="success">
          Email verified. Sign in to open your dashboard.
        </FormMessage>
      )}

      {login.isError && (
        <FormMessage>
          {login.error.message}
          {unverified && (
            <>
              {" "}
              <Link
                href={`/verify-email?email=${encodeURIComponent(getValues("email"))}`}
                className="font-medium underline underline-offset-4"
              >
                Resend the verification email
              </Link>
              .
            </>
          )}
        </FormMessage>
      )}

      <TextField
        id="login-email"
        label="Email address"
        type="email"
        inputMode="email"
        autoComplete="email"
        enterKeyHint="next"
        placeholder="owner@yourturf.com"
        error={errors.email?.message}
        {...register("email")}
      />

      <div className="space-y-2">
        <PasswordInput
          id="login-password"
          label="Password"
          autoComplete="current-password"
          enterKeyHint="go"
          placeholder="Enter your password"
          error={errors.password?.message}
          {...register("password")}
        />
        <div className="flex justify-end">
          <Link
            href="/forgot-password"
            className="rounded text-xs font-medium text-primary underline-offset-4 outline-none hover:underline focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            Forgot password?
          </Link>
        </div>
      </div>

      <SubmitButton pending={pending} pendingLabel="Signing in…">
        Sign In
      </SubmitButton>
    </form>
  );
}