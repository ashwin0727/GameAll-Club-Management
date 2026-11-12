import { redirect } from "next/navigation";
import { getCurrentProfile, getFacilityContext, getIsPlatformAdmin, getSetupReview } from "@/features/auth/api/auth.api";
import { SetupReviewPopup } from "@/features/setup-review/components/setup-review-popup";
import { AppShell } from "@/components/shared/app-shell";
import { NavigationProgress } from "@/components/shared/navigation-progress";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  // Both share the same cached auth.getUser() call under the hood, so
  // running them together costs one round trip instead of two sequential ones.
  const [profile, facilityContext] = await Promise.all([getCurrentProfile(), getFacilityContext()]);

  if (!profile) {
    redirect("/login");
  }

  // A staff account created by an administrator signs in with a one-time
  // password and must set their own before doing anything else.
  if (profile.must_reset_password) {
    redirect("/reset-password?forced=1");
  }

  // GameAll's own back-office account has no facility: it lives in /admin.
  if (!facilityContext && (await getIsPlatformAdmin())) {
    redirect("/admin");
  }

  // Setup finished but GameAll has not approved it yet (or sent it back): the dashboard stays usable, with a closable reminder.
  const review = facilityContext ? await getSetupReview() : null;
  const reviewStatus = review && (review.status === "PENDING" || review.status === "REJECTED") ? review.status : null;

  return (
    <AppShell profile={profile} facilityContext={facilityContext}>
      <NavigationProgress />
      {reviewStatus && review && <SetupReviewPopup status={reviewStatus} note={review.note} facilityId={review.facilityId} />}
      {children}
    </AppShell>
  );
}
