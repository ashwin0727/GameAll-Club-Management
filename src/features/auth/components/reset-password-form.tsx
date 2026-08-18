"use client";

import Link from "next/link";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { PasswordInput } from "@/features/auth/components/password-input";
import { PasswordStrengthMeter } from "@/features/auth/components/password-strength-meter";
import { FormMessage } from "@/features/auth/components/form-message";
import { useUpdatePassword } from "@/features/auth/hooks/use-auth";
import { MIN_PASSWORD_LENGTH, passwordSchema } from "@/features/auth/validation";

const resetPasswordSchema = z
  .object({
    password: passwordSchema,
    confirmPassword: z.string().min(1, "Confirm your password"),
  })
  .refine((values) => values.password === values.confirmPassword, {
    path: ["confirmPassword"],
    message: "Passwords do not match",
  });

type ResetPasswordInput = z.infer<typeof resetPasswordSchema>;

/**
 * Second half of the reset flow. Reached only through the emailed recovery
 * link, which establishes a short-lived session; without it `updateUser` fails
 * and the user is told to request a fresh link.
 */
export function ResetPasswordForm({ hasSession }: { hasSession: boolean }) {
  const updatePassword = useUpdatePassword();

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors, isSubmitting, isValid },
  } = useForm<ResetPasswordInput>({
    resolver: zodResolver(resetPasswordSchema),
    mode: "onTouched",
    defaultValues: { password: "", confirmPassword: "" },
  });

  if (!hasSession) {
    return (
      <div className="space-y-6">
        <FormMessage>
          This password reset link is invalid or has expired. Request a new one to continue.
        </FormMessage>
        <Button asChild className="h-11 w-full">
          <Link href="/forgot-password">Request a new link</Link>
        </Button>
      </div>
    );
  }

  return (
    <form
      onSubmit={handleSubmit((values) => updatePassword.mutate(values.password))}
      className="space-y-5"
      noValidate
    >
      {updatePassword.isError && <FormMessage>{updatePassword.error.message}</FormMessage>}

      <div>
        <PasswordInput
          id="reset-password"
          label="New password"
          autoComplete="new-password"
          enterKeyHint="next"
          placeholder={`At least ${MIN_PASSWORD_LENGTH} characters`}
          error={errors.password?.message}
          {...register("password")}
        />
        <PasswordStrengthMeter password={watch("password")} />
      </div>

      <PasswordInput
        id="reset-confirm-password"
        label="Confirm new password"
        autoComplete="new-password"
        enterKeyHint="go"
        placeholder="Re-enter your new password"
        error={errors.confirmPassword?.message}
        {...register("confirmPassword")}
      />

      <SubmitButton
        pending={updatePassword.isPending || isSubmitting}
        disabled={!isValid}
        pendingLabel="Updating password…"
      >
        Update Password
      </SubmitButton>
    </form>
  );
}