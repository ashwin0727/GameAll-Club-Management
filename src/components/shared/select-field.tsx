"use client";

import { useEffect, useId, useRef, useState } from "react";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

export interface SelectOption {
  value: string;
  label: string;
}

/**
 * A dropdown that draws its own list. A native <select>'s open list is painted
 * by the browser — square corners, a blue highlight — and can't be styled, so
 * this renders the same control ourselves: the list shares the field's 10px
 * radius; unselected rows are white, the chosen row carries the page colour
 * (#F7FDF9) and hover is the app's mint.
 * Keyboard: arrows move, Enter/Space picks, Escape closes.
 */
export function SelectField({
  value,
  onValueChange,
  options,
  ariaLabel,
  className,
  wrapperClassName,
  placement = "bottom",
}: {
  value: string;
  onValueChange: (value: string) => void;
  options: SelectOption[];
  ariaLabel?: string;
  /** Classes for the closed field (height, border, padding, text). */
  className?: string;
  wrapperClassName?: string;
  /**
   * Which way the list opens. Use "top" where the field sits at the bottom edge of a container
   * that clips its overflow, since a list opening downward would be cut off there.
   */
  placement?: "bottom" | "top";
}) {
  const listId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const selectedIndex = Math.max(
    0,
    options.findIndex((o) => o.value === value),
  );
  const [active, setActive] = useState(selectedIndex);
  const selected = options.find((o) => o.value === value);

  useEffect(() => {
    if (!open) return;
    function onDown(e: MouseEvent) {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  function openList() {
    setActive(selectedIndex);
    setOpen(true);
  }

  function pick(v: string) {
    onValueChange(v);
    setOpen(false);
  }

  return (
    <div ref={rootRef} className={cn("relative", wrapperClassName)}>
      <button
        type="button"
        role="combobox"
        aria-label={ariaLabel}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        onClick={() => (open ? setOpen(false) : openList())}
        onKeyDown={(e) => {
          if (e.key === "ArrowDown" || e.key === "ArrowUp") {
            e.preventDefault();
            if (!open) openList();
            else setActive((i) => Math.min(Math.max(i + (e.key === "ArrowDown" ? 1 : -1), 0), options.length - 1));
          } else if ((e.key === "Enter" || e.key === " ") && open) {
            e.preventDefault();
            const o = options[active];
            if (o) pick(o.value);
          } else if (e.key === "Escape" && open) {
            e.preventDefault();
            setOpen(false);
          }
        }}
        className={cn(
          "flex w-full items-center text-left outline-none transition-colors",
          className,
          "pr-11",
          open && "bg-[var(--light-page-bg)] dark:bg-card",
        )}
      >
        <span className="truncate">{selected?.label ?? ""}</span>
      </button>
      <ChevronDown
        aria-hidden
        className={cn(
          "pointer-events-none absolute right-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground transition-transform",
          open && "rotate-180",
        )}
      />

      {open && (
        <ul
          id={listId}
          role="listbox"
          className={cn(
            "absolute left-0 z-50 max-h-64 w-max min-w-full max-w-[320px] overflow-auto rounded-[10px] border border-border bg-white p-1 shadow-lg dark:bg-popover",
            placement === "top" ? "bottom-full mb-1" : "top-full mt-1",
          )}
        >
          {options.map((o, i) => (
            <li
              key={o.value}
              role="option"
              aria-selected={o.value === value}
              // mousedown, so the pick lands before anything can steal focus.
              onMouseDown={(e) => {
                e.preventDefault();
                pick(o.value);
              }}
              onMouseEnter={() => setActive(i)}
              className={cn(
                "cursor-pointer rounded-[8px] px-3 py-2 text-sm",
                // Unselected rows are plain white; the chosen one carries the page tint; hover is a light mint.
                o.value === value
                  ? "bg-[var(--light-page-bg)] font-semibold text-foreground dark:bg-accent/60"
                  : "bg-white text-foreground/90 dark:bg-transparent",
                i === active && o.value !== value && "bg-[#E9F9F3] dark:bg-accent",
              )}
            >
              {o.label}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
