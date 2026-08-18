import type { Metadata } from "next";
import { AuthCard } from "@/features/auth/components/auth-card";
import { ForgotPasswordForm } from "@/features/auth/components/forgot-password-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Reset your password — ${PRODUCT_NAME}`,
};

export default function ForgotPasswordPage() {
  return (
    <AuthCard
      title="Reset your password"
      subtitle="Enter your registered email address and we'll send you instructions to reset your password."
    >
      <ForgotPasswordForm />
    </AuthCard>
  );
}