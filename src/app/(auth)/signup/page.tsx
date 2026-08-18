import { Suspense } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import { AuthCard } from "@/features/auth/components/auth-card";
import { SignupForm } from "@/features/auth/components/signup-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Create your account — ${PRODUCT_NAME}`,
};

export default function SignupPage() {
  return (
    <AuthCard
      title="Create your account"
      subtitle="Start managing your sports facility smarter."
      footer={
        <>
          Already have an account?{" "}
          <Link
            href="/login"
            className="rounded font-medium text-primary underline-offset-4 outline-none hover:underline focus-visible:ring-2 focus-visible:ring-ring"
          >
            Sign In
          </Link>
        </>
      }
    >
      {/* The form reads ?email= for the "change email" round trip. */}
      <Suspense fallback={<div className="h-[420px]" />}>
        <SignupForm />
      </Suspense>
    </AuthCard>
  );
}