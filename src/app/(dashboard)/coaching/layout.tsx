import { getFacilityContext } from "@/features/auth/api/auth.api";
import { PermissionDenied } from "@/features/staff/components/permission-denied";

/**
 * Server-side route guard for the whole Coaching section. The database
 * (has_permission + RLS on every RPC) is the real boundary — this only
 * avoids rendering a workspace the user cannot use.
 */
export default async function CoachingLayout({ children }: { children: React.ReactNode }) {
  const context = await getFacilityContext();
  const allowed = context && (context.baseRole === "owner" || context.permissions.includes("COACHING_VIEW"));

  if (!allowed) {
    return <PermissionDenied message="You don't have permission to view coaching." />;
  }

  return <>{children}</>;
}
