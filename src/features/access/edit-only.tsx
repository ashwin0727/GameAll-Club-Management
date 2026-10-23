"use client";

import { useCanEditHere, usePermission, usePermissionContext } from "@/features/auth/context/permission-provider";
import type { PageKey } from "@/features/access/access";
import type { PermissionKey } from "@/features/staff/types";

/**
 * Renders its children only for a person with Edit on the page they're looking at. Wrap anything that creates, changes,
 * cancels, records or exports: View-only roles see the data, never the controls.
 */
export function EditOnly({ children }: { children: React.ReactNode }) {
  return useCanEditHere() ? <>{children}</> : null;
}

/** Renders its children only when the person holds the specific permission key (e.g. a sensitive action on a page). */
export function RequirePermission({ permission, children }: { permission: PermissionKey; children: React.ReactNode }) {
  return usePermission(permission) ? <>{children}</> : null;
}

/**
 * Renders its children only when the person can view at least one of the given pages (a "view" gate, for dashboard
 * widgets that summarise another page: a revenue card needs Finance or Reports, a members card needs Memberships…).
 */
export function PageGate({ pages, children }: { pages: PageKey[]; children: React.ReactNode }) {
  const ctx = usePermissionContext();
  if (ctx && !pages.some((p) => ctx.canViewPage(p))) return null;
  return <>{children}</>;
}
