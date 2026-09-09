"use client";

import { createContext, useContext, useMemo } from "react";
import type { FacilityContext } from "@/features/auth/api/auth.api";
import type { PermissionKey } from "@/features/staff/types";

interface PermissionContextValue {
  facilityId: string;
  facilityName: string;
  baseRole: "owner" | "manager" | "staff";
  permissions: ReadonlySet<string>;
  /** UX only — the database (has_permission + RLS) is the real boundary. */
  can: (key: PermissionKey) => boolean;
  canAny: (...keys: PermissionKey[]) => boolean;
}

const PermissionContext = createContext<PermissionContextValue | null>(null);

export function PermissionProvider({
  context,
  children,
}: {
  context: FacilityContext;
  children: React.ReactNode;
}) {
  const value = useMemo<PermissionContextValue>(() => {
    const set = new Set(context.permissions);
    // A facility owner implicitly holds everything, mirroring has_permission.
    const can = (key: PermissionKey) => context.baseRole === "owner" || set.has(key);
    return {
      facilityId: context.facilityId,
      facilityName: context.facilityName,
      baseRole: context.baseRole,
      permissions: set,
      can,
      canAny: (...keys: PermissionKey[]) => keys.some(can),
    };
  }, [context]);

  return <PermissionContext.Provider value={value}>{children}</PermissionContext.Provider>;
}

/** The active facility's permission context. Null outside the dashboard shell
 *  (e.g. onboarding, before a facility exists). */
export function usePermissionContext(): PermissionContextValue | null {
  return useContext(PermissionContext);
}

/** True when the signed-in user holds `key` for the active facility. Returns
 *  false when there is no facility context yet. */
export function usePermission(key: PermissionKey): boolean {
  return useContext(PermissionContext)?.can(key) ?? false;
}
