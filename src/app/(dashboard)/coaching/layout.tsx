import { getFacilityContext } from "@/features/auth/api/auth.api";
import { canViewAnyPage } from "@/features/access/access";
import { PermissionDenied } from "@/features/staff/components/permission-denied";

/**
 * Server-side route guard for the whole Coaching section. The database
 * (has_permission + RLS on every RPC) is the real boundary — this only
 * avoids rendering a workspace the user cannot use.
 */
export default async function CoachingLayout({ children }: { children: React.ReactNode }) {
  const context = await getFacilityContext();
  // Any Coaching page will do: each page is then guarded on its own (RouteGuard here, has_permission in the database).
  const allowed = context && canViewAnyPage(context.permissions, context.baseRole === "owner", ["COACHING_"]);

  if (!allowed) {
    return <PermissionDenied message="You don't have permission to view coaching." />;
  }

  return <>{children}</>;
}
