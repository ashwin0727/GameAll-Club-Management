"use client";

import { useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { TextField } from "@/features/auth/components/text-field";
import { PasswordInput } from "@/features/auth/components/password-input";
import { PasswordStrengthMeter } from "@/features/auth/components/password-strength-meter";
import { FormMessage } from "@/features/auth/components/form-message";
import { usePendingSignup } from "@/features/auth/context/pending-signup";
import { useSignup } from "@/features/auth/hooks/use-auth";
import { MIN_PASSWORD_LENGTH, signupSchema, type SignupInput } from "@/features/auth/validation";

export function SignupForm() {
  const signup = useSignup();
  const { setPending } = usePendingSignup();
  const searchParams = useSearchParams();
  const prefilledEmail = searchParams.get("email") ?? "";

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors, isSubmitting, isValid },
  } = useForm<SignupInput>({
    resolver: zodResolver(signupSchema),
    // Validate on blur, then live once a field has been touched: obvious
    // mistakes surface immediately without scolding a half-typed email.
    mode: "onTouched",
    defaultValues: { name: "", email: prefilledEmail, password: "", confirmPassword: "" },
  });

  // Arriving from "Change email address" carries the address to correct.
  useEffect(() => {
    if (prefilledEmail) setValue("email", prefilledEmail);
  }, [prefilledEmail, setValue]);

  const password = watch("password");
  const pending = signup.isPending || isSubmitting;

  const onSubmit = (values: SignupInput) => {
    // Kept in memory only, so /verify-email can re-issue the confirmation to a
    // corrected address without a second round of typing.
    setPending({ name: values.name, email: values.email, password: values.password });
    signup.mutate(values);
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-5" noValidate>
      {signup.isError && <FormMessage>{signup.error.message}</FormMessage>}

      <TextField
        id="signup-name"
        label="Full name"
        autoComplete="name"
        enterKeyHint="next"
        placeholder="Ravi Kumar"
        error={errors.name?.message}
        {...register("name")}
      />

      <TextField
        id="signup-email"
        label="Business email"
        type="email"
        inputMode="email"
        autoComplete="email"
        enterKeyHint="next"
        placeholder="owner@yourturf.com"
        error={errors.email?.message}
        {...register("email")}
      />

      <div>
        <PasswordInput
          id="signup-password"
          label="Password"
          autoComplete="new-password"
          enterKeyHint="next"
          placeholder={`At least ${MIN_PASSWORD_LENGTH} characters`}
          error={errors.password?.message}
          {...register("password")}
        />
        <PasswordStrengthMeter password={password} />
      </div>

      <PasswordInput
        id="signup-confirm-password"
        label="Confirm password"
        autoComplete="new-password"
        enterKeyHint="done"
        placeholder="Re-enter your password"
        error={errors.confirmPassword?.message}
        {...register("confirmPassword")}
      />

      {/* Stays disabled until every field passes, per the signup spec. Each
          field shows its own inline reason, so the block is never unexplained. */}
      <SubmitButton pending={pending} disabled={!isValid} pendingLabel="Creating account…">
        Create Account
      </SubmitButton>

      <p className="text-center text-xs leading-relaxed text-muted-foreground">
        We&apos;ll email you a link to confirm this address before your first sign-in.
      </p>
    </form>
  );
}