import { getFacilityContext } from "@/features/auth/api/auth.api";
import { PermissionDenied } from "@/features/staff/components/permission-denied";

/**
 * Server-side route guard for the whole Users & Roles section. The database
 * (has_permission + RLS on every RPC) is the real boundary — this just avoids
 * rendering a workspace the user cannot use, and returns an honest state
 * rather than a broken page.
 */
export default async function UsersRolesLayout({ children }: { children: React.ReactNode }) {
  const context = await getFacilityContext();
  const allowed =
    context && (context.baseRole === "owner" || context.permissions.includes("USERS_VIEW"));

  if (!allowed) {
    return <PermissionDenied message="You don't have permission to manage staff and roles." />;
  }

  return <>{children}</>;
}
