import { Suspense } from "react";
import type { Metadata } from "next";
import { AuthCard } from "@/features/auth/components/auth-card";
import { VerifyEmailPanel } from "@/features/auth/components/verify-email-panel";

export const metadata: Metadata = {
  title: `Verify your email`,
};

export default function VerifyEmailPage() {
  return (
    <AuthCard title="Verify Your Email">
      <Suspense fallback={<div className="h-[380px]" />}>
        <VerifyEmailPanel />
      </Suspense>
    </AuthCard>
  );
}