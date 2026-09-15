import { AuthCard } from "@/features/auth/components/auth-card";
import { AuthFormSkeleton, AuthFooterLinkSkeleton } from "@/features/auth/components/auth-form-skeleton";

/**
 * Shown while navigating to /signup. Reuses the real AuthCard chrome (brand
 * mark, heading, subtitle) so only the form fields skeleton in, matching the
 * final layout instead of a generic spinner.
 */
export default function SignupLoading() {
  return (
    <AuthCard
      title="Create your account"
      subtitle="Start managing your sports facility smarter."
      footer={<AuthFooterLinkSkeleton />}
    >
      <AuthFormSkeleton fields={4} />
    </AuthCard>
  );
}
