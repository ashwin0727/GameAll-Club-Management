import type { Metadata } from "next";
import { LoginForm } from "@/features/auth/components/login-form";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Sign in — ${APP_NAME}`,
};

export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-1 text-center">
          <h1 className="text-xl font-semibold">{APP_NAME}</h1>
          <p className="text-sm text-muted-foreground">Sign in to manage your club</p>
        </div>
        <LoginForm />
      </div>
    </div>
  );
}