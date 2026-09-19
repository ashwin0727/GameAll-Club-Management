import { AuthCard } from "@/features/auth/components/auth-card";
import { AuthFormSkeleton, AuthFooterLinkSkeleton } from "@/features/auth/components/auth-form-skeleton";

/**
 * Shown while navigating to /login. Reuses the real AuthCard chrome (brand
 * mark, heading, subtitle) so only the form fields skeleton in, matching the
 * final layout instead of a generic spinner.
 */
export default function LoginLoading() {
  return (
    <AuthCard
      title="Welcome back"
      subtitle="Sign in to manage your facility."
      footer={<AuthFooterLinkSkeleton />}
    >
      <AuthFormSkeleton fields={2} />
    </AuthCard>
  );
}
