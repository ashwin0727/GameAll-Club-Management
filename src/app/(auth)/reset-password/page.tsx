import type { Metadata } from "next";
import { AuthCard } from "@/features/auth/components/auth-card";
import { ResetPasswordForm } from "@/features/auth/components/reset-password-form";
import { createClient } from "@/lib/supabase/server";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Choose a new password — ${PRODUCT_NAME}`,
};

/**
 * Reached from the emailed recovery link, which /auth/callback has already
 * exchanged for a session. Without that session there is nothing to update, so
 * the session check happens here rather than inside the form.
 */
export default async function ResetPasswordPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <AuthCard
      title="Choose a new password"
      subtitle={
        user
          ? "Pick a password you haven't used on this account before."
          : "This reset link is no longer valid."
      }
    >
      <ResetPasswordForm hasSession={Boolean(user)} />
    </AuthCard>
  );
}