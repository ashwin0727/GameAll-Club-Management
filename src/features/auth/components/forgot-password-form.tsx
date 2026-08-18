"use client";

import Link from "next/link";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { MailCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { TextField } from "@/features/auth/components/text-field";
import { FormMessage } from "@/features/auth/components/form-message";
import { useResetPassword } from "@/features/auth/hooks/use-auth";
import { forgotPasswordSchema, type ForgotPasswordInput } from "@/features/auth/validation";

export function ForgotPasswordForm() {
  const reset = useResetPassword();

  const {
    register,
    handleSubmit,
    getValues,
    formState: { errors, isSubmitting },
  } = useForm<ForgotPasswordInput>({
    resolver: zodResolver(forgotPasswordSchema),
    mode: "onTouched",
    defaultValues: { email: "" },
  });

  // Deliberately the same confirmation whether or not the address exists —
  // the screen must not become an account-enumeration oracle.
  if (reset.isSuccess) {
    return (
      <div className="space-y-6 text-center">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-success/10">
          <MailCheck className="h-6 w-6 text-success" aria-hidden="true" />
        </div>
        <div className="space-y-2">
          <h2 className="text-base font-semibold">Check your inbox</h2>
          <p className="text-sm leading-relaxed text-muted-foreground">
            If an account exists for{" "}
            <span className="font-medium text-foreground">{getValues("email")}</span>, reset
            instructions are on their way. The link is valid for one hour.
          </p>
        </div>
        <Button asChild variant="outline" className="h-11 w-full">
          <Link href="/login">Back to Sign In</Link>
        </Button>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit((values) => reset.mutate(values))} className="space-y-5" noValidate>
      {reset.isError && <FormMessage>{reset.error.message}</FormMessage>}

      <TextField
        id="forgot-email"
        label="Registered email address"
        type="email"
        inputMode="email"
        autoComplete="email"
        enterKeyHint="go"
        placeholder="owner@yourturf.com"
        error={errors.email?.message}
        {...register("email")}
      />

      <SubmitButton pending={reset.isPending || isSubmitting} pendingLabel="Sending…">
        Send Reset Link
      </SubmitButton>

      <Button asChild variant="ghost" className="h-11 w-full">
        <Link href="/login">Back to Sign In</Link>
      </Button>
    </form>
  );
}