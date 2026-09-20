"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Search } from "lucide-react";
import { NAV_ITEMS } from "@/lib/constants";
import type { Role } from "@/types/database.types";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { PermissionKey } from "@/features/staff/types";
import { cn } from "@/lib/utils";

interface SearchEntry {
  label: string;
  href: string;
  /** Section the page lives under, shown as a hint beside the result. */
  section: string;
}

/**
 * "Search anything" — jumps to any page the user can open. It searches the same
 * navigation the sidebar shows, gated by the same role/permission rules, so it
 * can never surface a page the sidebar would hide.
 */
export function TopbarSearch({ role }: { role: Role }) {
  const router = useRouter();
  const perms = usePermissionContext();
  const inputRef = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);

  const entries = useMemo<SearchEntry[]>(() => {
    const out: SearchEntry[] = [];
    for (const item of NAV_ITEMS) {
      if (!item.roles.includes(role)) continue;
      if (item.permission && perms && !perms.can(item.permission as PermissionKey)) continue;
      out.push({ label: item.label, href: item.href, section: "Page" });
      for (const child of item.children ?? []) {
        if (child.href === item.href) continue;
        out.push({ label: child.label, href: child.href, section: item.label });
      }
    }
    return out;
  }, [role, perms]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return [];
    return entries
      .filter((e) => e.label.toLowerCase().includes(q) || e.section.toLowerCase().includes(q))
      .slice(0, 6);
  }, [entries, query]);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        inputRef.current?.focus();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  function go(entry: SearchEntry) {
    setQuery("");
    setOpen(false);
    inputRef.current?.blur();
    router.push(entry.href);
  }

  return (
    <div className="relative hidden w-full max-w-[300px] md:block">
      <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
      <input
        ref={inputRef}
        type="text"
        role="combobox"
        aria-label="Search pages"
        aria-expanded={open && results.length > 0}
        aria-controls="topbar-search-results"
        placeholder="Search anything..."
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          setActive(0);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onKeyDown={(e) => {
          if (e.key === "ArrowDown") {
            e.preventDefault();
            setActive((i) => Math.min(i + 1, results.length - 1));
          } else if (e.key === "ArrowUp") {
            e.preventDefault();
            setActive((i) => Math.max(i - 1, 0));
          } else if (e.key === "Enter" && results[active]) {
            e.preventDefault();
            go(results[active]!);
          } else if (e.key === "Escape") {
            setQuery("");
            setOpen(false);
            inputRef.current?.blur();
          }
        }}
        className="h-10 w-full rounded-lg border border-input bg-card pl-9 pr-16 text-sm outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
      />
      <span className="pointer-events-none absolute right-2 top-1/2 flex -translate-y-1/2 gap-1" aria-hidden>
        <kbd className="rounded border border-border bg-secondary px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">Ctrl</kbd>
        <kbd className="rounded border border-border bg-secondary px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">K</kbd>
      </span>
      {open && query.trim() && (
        <ul
          id="topbar-search-results"
          role="listbox"
          className="absolute left-0 right-0 top-full z-50 mt-1 overflow-hidden rounded-lg border border-border bg-popover p-1 text-popover-foreground shadow-lg"
        >
          {results.length === 0 ? (
            <li className="px-3 py-2 text-xs text-muted-foreground">No matching pages.</li>
          ) : (
            results.map((r, i) => (
              <li
                key={r.href}
                role="option"
                aria-selected={i === active}
                // mousedown fires before the input's blur closes the list.
                onMouseDown={(e) => {
                  e.preventDefault();
                  go(r);
                }}
                onMouseEnter={() => setActive(i)}
                className={cn(
                  "flex cursor-pointer items-center justify-between gap-2 rounded-md px-3 py-2 text-sm",
                  i === active && "bg-accent text-accent-foreground",
                )}
              >
                <span className="truncate">{r.label}</span>
                <span className="shrink-0 text-[11px] text-muted-foreground">{r.section}</span>
              </li>
            ))
          )}
        </ul>
      )}
    </div>
  );
}
