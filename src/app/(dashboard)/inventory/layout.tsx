import { getFacilityContext } from "@/features/auth/api/auth.api";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { INVENTORY_ENABLED } from "@/lib/constants";

/**
 * Server-side route guard for the whole Inventory & Vendors section. The
 * database (has_permission + RLS on every RPC) is the real boundary — this
 * only avoids rendering a workspace the user cannot use.
 */
export default async function InventoryLayout({ children }: { children: React.ReactNode }) {
  if (!INVENTORY_ENABLED) {
    return <PermissionDenied message="Inventory management is currently unavailable." />;
  }

  const context = await getFacilityContext();
  const allowed =
    context && (context.baseRole === "owner" || context.permissions.includes("INVENTORY_VIEW"));

  if (!allowed) {
    return <PermissionDenied message="You don't have permission to view inventory and vendors." />;
  }

  return <>{children}</>;
}
