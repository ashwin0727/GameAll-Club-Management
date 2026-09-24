"use client";

import { useEffect, useId, useRef, useState } from "react";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

export interface MemberSelectOption {
  value: string;
  label: string;
  sublabel?: string;
}

function initials(name: string): string {
  return name.split(" ").filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join("");
}

const AVATAR_TONES = [
  "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  "bg-success/15 text-success",
  "bg-purple-500/15 text-purple-600 dark:text-purple-400",
  "bg-warning/15 text-warning",
  "bg-destructive/15 text-destructive",
];

function toneFor(value: string): string {
  let hash = 0;
  for (let i = 0; i < value.length; i++) hash = (hash * 31 + value.charCodeAt(i)) >>> 0;
  return AVATAR_TONES[hash % AVATAR_TONES.length]!;
}

function Avatar({ name, value, size = "h-8 w-8" }: { name: string; value: string; size?: string }) {
  return (
    <span className={cn("flex shrink-0 items-center justify-center rounded-full text-xs font-semibold", size, toneFor(value))}>
      {initials(name)}
    </span>
  );
}

/**
 * Like `SelectField`, but each row (and the closed field) shows a round initials avatar beside
 * the name — matching the "Select Member" control in the design. There's no member photo
 * column yet, so the avatar is the same initials-in-a-circle treatment used elsewhere
 * (`MemberContextPanel`, `MemberScheduleDetailsPanel`), just inline instead of full-size.
 */
export function MemberSelectField({
  value,
  onValueChange,
  options,
  ariaLabel,
  placeholder = "Select a member",
}: {
  value: string;
  onValueChange: (value: string) => void;
  options: MemberSelectOption[];
  ariaLabel?: string;
  placeholder?: string;
}) {
  const listId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const selected = options.find((o) => o.value === value);
  const filtered = query.trim()
    ? options.filter((o) => `${o.label} ${o.sublabel ?? ""}`.toLowerCase().includes(query.trim().toLowerCase()))
    : options;
  const [active, setActive] = useState(0);

  useEffect(() => {
    if (!open) return;
    setQuery("");
    // Focus the search box once the field opens, so typing starts filtering immediately.
    const id = requestAnimationFrame(() => searchRef.current?.focus());
    function onDown(e: MouseEvent) {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    return () => {
      cancelAnimationFrame(id);
      document.removeEventListener("mousedown", onDown);
    };
  }, [open]);

  // Filtering can shrink the list out from under the highlighted row — keep `active` in range.
  useEffect(() => {
    setActive((i) => Math.min(i, Math.max(filtered.length - 1, 0)));
  }, [filtered.length]);

  function openList() {
    setActive(Math.max(0, options.findIndex((o) => o.value === value)));
    setOpen(true);
  }

  function pick(v: string) {
    onValueChange(v);
    setOpen(false);
  }

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        role="combobox"
        aria-label={ariaLabel}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        onClick={() => (open ? setOpen(false) : openList())}
        className={cn(
          "flex h-10 w-full items-center gap-2 rounded-[6px] border border-input bg-card px-2.5 pr-9 text-left text-sm outline-none transition-colors hover:border-foreground/30",
          open && "border-foreground/40",
        )}
      >
        {selected ? (
          <>
            <Avatar name={selected.label} value={selected.value} />
            <span className="min-w-0 flex-1 truncate font-medium text-foreground">{selected.label}</span>
          </>
        ) : (
          <span className="flex-1 truncate text-muted-foreground/60">{placeholder}</span>
        )}
      </button>
      <ChevronDown
        aria-hidden
        className={cn(
          "pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground transition-transform",
          open && "rotate-180",
        )}
      />

      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 w-full min-w-[240px] max-w-[320px] rounded-[10px] border border-border bg-white p-1.5 shadow-lg dark:bg-popover">
          <input
            ref={searchRef}
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search members…"
            aria-label="Search members"
            onKeyDown={(e) => {
              if (e.key === "ArrowDown" || e.key === "ArrowUp") {
                e.preventDefault();
                setActive((i) => Math.min(Math.max(i + (e.key === "ArrowDown" ? 1 : -1), 0), filtered.length - 1));
              } else if (e.key === "Enter") {
                e.preventDefault();
                const o = filtered[active];
                if (o) pick(o.value);
              } else if (e.key === "Escape") {
                e.preventDefault();
                setOpen(false);
              }
            }}
            className="mb-1 w-full rounded-[6px] border border-input bg-card px-2.5 py-1.5 text-sm text-foreground outline-none placeholder:text-muted-foreground/60 focus-visible:border-foreground/40"
          />
          <ul id={listId} role="listbox" className="max-h-64 overflow-auto">
            {filtered.length === 0 && <li className="px-2.5 py-2 text-sm text-muted-foreground">No members found.</li>}
            {filtered.map((o, i) => (
              <li
                key={o.value}
                role="option"
                aria-selected={o.value === value}
                onMouseDown={(e) => {
                  e.preventDefault();
                  pick(o.value);
                }}
                onMouseEnter={() => setActive(i)}
                className={cn(
                  "flex cursor-pointer items-center gap-2 rounded-[8px] px-2.5 py-2 text-sm",
                  o.value === value ? "bg-[var(--light-page-bg)] dark:bg-accent/60" : "bg-white dark:bg-transparent",
                  i === active && o.value !== value && "bg-[#E9F9F3] dark:bg-accent",
                )}
              >
                <Avatar name={o.label} value={o.value} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-medium text-foreground">{o.label}</span>
                  {o.sublabel && <span className="block truncate text-xs text-muted-foreground">{o.sublabel}</span>}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
