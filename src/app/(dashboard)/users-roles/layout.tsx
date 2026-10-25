import { getFacilityContext } from "@/features/auth/api/auth.api";
import { canViewAnyPage } from "@/features/access/access";
import { PermissionDenied } from "@/features/staff/components/permission-denied";

/**
 * Server-side route guard for the whole Users & Roles section. The database
 * (has_permission + RLS on every RPC) is the real boundary — this just avoids
 * rendering a workspace the user cannot use, and returns an honest state
 * rather than a broken page.
 */
export default async function UsersRolesLayout({ children }: { children: React.ReactNode }) {
  const context = await getFacilityContext();
  const allowed = context && canViewAnyPage(context.permissions, context.baseRole === "owner", ["STAFF", "ROLES", "ACCESS_HISTORY"]);

  if (!allowed) {
    return <PermissionDenied message="You don't have permission to manage staff and roles." />;
  }

  return <>{children}</>;
}
