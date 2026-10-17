import { Suspense } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import { AuthCard } from "@/features/auth/components/auth-card";
import { LoginForm } from "@/features/auth/components/login-form";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Sign in — ${PRODUCT_NAME}`,
};

export default function LoginPage() {
  return (
    <AuthCard
      title="Welcome Back"
      subtitle="Sign in to manage your facility."
      footer={
        <>
          Don&apos;t have an account?{" "}
          <Link
            href="/signup"
            className="rounded font-medium text-primary underline-offset-4 outline-none hover:underline focus-visible:ring-2 focus-visible:ring-ring"
          >
            Create Account
          </Link>
        </>
      }
    >
      <Suspense fallback={<div className="h-[300px]" />}>
        <LoginForm />
      </Suspense>
    </AuthCard>
  );
}