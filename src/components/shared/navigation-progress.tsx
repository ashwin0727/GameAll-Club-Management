"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";

/**
 * A thin progress bar across the top of the app that shows the moment an in-app link is clicked and goes away
 * once the new page has arrived. Next only swaps the page after the next route has compiled / streamed in, so
 * without this a click on a slow route looks like nothing happened.
 */
export function NavigationProgress() {
  const pathname = usePathname();
  const [pending, setPending] = useState(false);

  // The new page arrived.
  useEffect(() => {
    setPending(false);
  }, [pathname]);

  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      const anchor = (e.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!anchor || anchor.target === "_blank" || anchor.hasAttribute("download")) return;
      const url = new URL(anchor.href, window.location.href);
      if (url.origin !== window.location.origin) return;
      if (url.pathname === window.location.pathname) return; // same page / hash or query change
      setPending(true);
    }
    document.addEventListener("click", onClick);
    return () => document.removeEventListener("click", onClick);
  }, []);

  // Never leave the bar stuck if the navigation fails.
  useEffect(() => {
    if (!pending) return;
    const t = setTimeout(() => setPending(false), 15000);
    return () => clearTimeout(t);
  }, [pending]);

  if (!pending) return null;
  return (
    <div role="progressbar" aria-label="Loading page" className="pointer-events-none fixed inset-x-0 top-0 z-[100] h-0.5 overflow-hidden bg-primary/15">
      <div className="h-full w-1/3 animate-[nav-progress_1.1s_ease-in-out_infinite] rounded-full bg-primary" />
    </div>
  );
}
