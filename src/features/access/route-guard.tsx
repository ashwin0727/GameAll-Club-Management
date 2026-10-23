"use client";

import { useEffect } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Lock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { NAV_ITEMS } from "@/lib/constants";
import { usePermissionContext } from "@/features/auth/context/permission-provider";

/**
 * Keeps the page itself out of reach, not just its menu entry: typing a URL, following an old link or a shortcut
 * lands on "no access" unless the person's role grants that page (Edit for create / edit sub-pages). When the Home page
 * is the one that's missing, they are sent to the first page they can open instead of a dead end.
 */
export function RouteGuard({ children }: { children: React.ReactNode }) {
  const perms = usePermissionContext();
  const pathname = usePathname() ?? "";
  const router = useRouter();

  const allowed = perms ? perms.canAccessPath(pathname) : true;
  const fallback = perms && !allowed ? NAV_ITEMS.find((i) => perms.canAccessPath(i.href))?.href ?? null : null;
  const redirectHome = !allowed && pathname === "/dashboard" && fallback;

  useEffect(() => {
    if (redirectHome) router.replace(redirectHome);
  }, [redirectHome, router]);

  if (allowed) return <>{children}</>;
  if (redirectHome) return null;

  return (
    <div className="mx-auto mt-16 flex max-w-md flex-col items-center gap-3 rounded-2xl border border-border bg-card p-10 text-center">
      <span className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
        <Lock className="h-5 w-5 text-muted-foreground" aria-hidden />
      </span>
      <h1 className="text-lg font-semibold">You don&apos;t have access to this page</h1>
      <p className="text-sm text-muted-foreground">
        Your role doesn&apos;t include this page. Ask the facility owner to update your access if you need it.
      </p>
      {fallback && (
        <Button asChild>
          <Link href={fallback}>Go to an available page</Link>
        </Button>
      )}
    </div>
  );
}
