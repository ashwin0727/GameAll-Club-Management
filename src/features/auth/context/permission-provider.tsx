"use client";

import { createContext, useContext, useMemo } from "react";
import { usePathname } from "next/navigation";
import type { FacilityContext } from "@/features/auth/api/auth.api";
import type { PermissionKey } from "@/features/staff/types";
import { COACHING_OWN_ONLY, accessPage, levelFor, type AccessLevel, type PageKey } from "@/features/access/access";
import { pageForPath } from "@/features/access/routes";

interface PermissionContextValue {
  facilityId: string;
  facilityName: string;
  baseRole: "owner" | "manager" | "staff";
  permissions: ReadonlySet<string>;
  /** UX only — the database (has_permission + RLS) is the real boundary. */
  can: (key: PermissionKey) => boolean;
  canAny: (...keys: PermissionKey[]) => boolean;
  /** None / View / Edit on a page of the access matrix. Owners have Edit everywhere. */
  pageLevel: (page: PageKey) => AccessLevel;
  canViewPage: (page: PageKey) => boolean;
  /** Edit on the page: may create, change, cancel, record and export there. */
  canEditPage: (page: PageKey) => boolean;
  /** Whether the person may open this dashboard URL (Edit for create / edit sub-pages). Unmapped URLs are open. */
  canAccessPath: (path: string) => boolean;
  /** Coach-style role: Coaching shows only their own coach profile, sessions, programs and students. */
  coachingOwnOnly: boolean;
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
    const isOwner = context.baseRole === "owner";
    const pageLevel = (page: PageKey): AccessLevel => {
      const def = accessPage(page);
      return def ? levelFor(def, set, isOwner) : "none";
    };
    return {
      facilityId: context.facilityId,
      facilityName: context.facilityName,
      baseRole: context.baseRole,
      permissions: set,
      can,
      canAny: (...keys: PermissionKey[]) => keys.some(can),
      pageLevel,
      canViewPage: (page) => pageLevel(page) !== "none",
      canEditPage: (page) => pageLevel(page) === "edit",
      canAccessPath: (path) => {
        const hit = pageForPath(path);
        if (!hit) return true;
        const level = pageLevel(hit.page);
        return hit.needs === "edit" ? level === "edit" : level !== "none";
      },
      coachingOwnOnly: context.baseRole !== "owner" && set.has(COACHING_OWN_ONLY),
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
/** None / View / Edit for one page, e.g. `const { canEdit } = usePageAccess("GUEST_PLAYERS")`. Open (edit) outside the
 *  dashboard shell, where there is no facility context to restrict. */
export function usePageAccess(page: PageKey): { level: AccessLevel; canView: boolean; canEdit: boolean } {
  const ctx = useContext(PermissionContext);
  const level: AccessLevel = ctx ? ctx.pageLevel(page) : "edit";
  return { level, canView: level !== "none", canEdit: level === "edit" };
}

export function usePermission(key: PermissionKey): boolean {
  return useContext(PermissionContext)?.can(key) ?? false;
}

/**
 * True when the person has Edit on the page the current URL belongs to — the gate for anything that creates, changes,
 * cancels, records or exports on it. Open (true) outside the dashboard shell and on URLs no page guards.
 */
export function useCanEditHere(): boolean {
  const ctx = useContext(PermissionContext);
  const pathname = usePathname() ?? "";
  if (!ctx) return true;
  const hit = pageForPath(pathname);
  return hit ? ctx.canEditPage(hit.page) : true;
}
