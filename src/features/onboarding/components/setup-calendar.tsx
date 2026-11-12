"use client";

import * as React from "react";
import { addDays, addMonths, endOfMonth, endOfWeek, format, isSameDay, isSameMonth, parseISO, startOfMonth, startOfWeek } from "date-fns";
import { CalendarDays, ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";

const iso = (d: Date) => format(d, "yyyy-MM-dd");
const WEEKDAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];

/**
 * A month calendar in the setup look. Monday first, today ringed, dates before [min] greyed and unselectable, and fully usable from the
 * keyboard the way the WAI-ARIA date-picker pattern asks: arrow keys move by a day / week, Home / End to the start / end of the week,
 * Page Up / Page Down by a month, Enter or Space to pick.
 */
export function SetupCalendar({
  value,
  onSelect,
  min,
  autoFocus = false,
  className,
}: {
  /** The chosen date, "yyyy-MM-dd", or "". */
  value: string;
  onSelect: (iso: string) => void;
  /** The earliest date that can be picked, "yyyy-MM-dd". */
  min?: string;
  autoFocus?: boolean;
  className?: string;
}) {
  const selected = value ? parseISO(value) : null;
  const minDate = min ? parseISO(min) : null;
  const [focusDay, setFocusDay] = React.useState<Date>(() => selected ?? (minDate && minDate > new Date() ? minDate : new Date()));
  const gridRef = React.useRef<HTMLDivElement>(null);
  const shouldFocus = React.useRef(autoFocus);

  const month = startOfMonth(focusDay);
  const days = React.useMemo(() => {
    const out: Date[] = [];
    for (let d = startOfWeek(startOfMonth(focusDay), { weekStartsOn: 1 }); d <= endOfWeek(endOfMonth(focusDay), { weekStartsOn: 1 }); d = addDays(d, 1)) out.push(d);
    return out;
  }, [focusDay]);

  const isOff = (d: Date) => minDate != null && iso(d) < iso(minDate);

  React.useEffect(() => {
    if (!shouldFocus.current) return;
    gridRef.current?.querySelector<HTMLButtonElement>('button[tabindex="0"]')?.focus();
  }, [focusDay]);

  function move(next: Date) {
    shouldFocus.current = true;
    setFocusDay(next);
  }

  function onKeyDown(e: React.KeyboardEvent) {
    const keys: Record<string, () => Date> = {
      ArrowLeft: () => addDays(focusDay, -1),
      ArrowRight: () => addDays(focusDay, 1),
      ArrowUp: () => addDays(focusDay, -7),
      ArrowDown: () => addDays(focusDay, 7),
      Home: () => startOfWeek(focusDay, { weekStartsOn: 1 }),
      End: () => endOfWeek(focusDay, { weekStartsOn: 1 }),
      PageUp: () => addMonths(focusDay, -1),
      PageDown: () => addMonths(focusDay, 1),
    };
    const next = keys[e.key];
    if (next) {
      e.preventDefault();
      move(next());
    }
  }

  return (
    <div className={cn("w-[272px] max-w-full select-none", className)}>
      <div className="mb-2 flex items-center justify-between">
        <button
          type="button"
          aria-label="Previous month"
          onClick={() => move(addMonths(focusDay, -1))}
          className="flex h-8 w-8 items-center justify-center rounded-lg hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
        >
          <ChevronLeft className="h-4 w-4" aria-hidden="true" />
        </button>
        <p className="text-sm font-semibold" aria-live="polite">
          {format(month, "MMMM yyyy")}
        </p>
        <button
          type="button"
          aria-label="Next month"
          onClick={() => move(addMonths(focusDay, 1))}
          className="flex h-8 w-8 items-center justify-center rounded-lg hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
        >
          <ChevronRight className="h-4 w-4" aria-hidden="true" />
        </button>
      </div>

      <div className="grid grid-cols-7 text-center text-[11px] font-semibold text-[#666666]" aria-hidden="true">
        {WEEKDAYS.map((d) => (
          <span key={d} className="py-1">
            {d}
          </span>
        ))}
      </div>

      <div ref={gridRef} role="grid" aria-label={format(month, "MMMM yyyy")} onKeyDown={onKeyDown} className="grid grid-cols-7 gap-y-0.5">
        {days.map((day) => {
          const inMonth = isSameMonth(day, month);
          const isSelected = selected != null && isSameDay(day, selected);
          const off = isOff(day);
          const isToday = isSameDay(day, new Date());
          const focusable = isSameDay(day, focusDay);
          return (
            <button
              key={iso(day)}
              type="button"
              role="gridcell"
              tabIndex={focusable ? 0 : -1}
              disabled={off}
              aria-label={format(day, "d MMMM yyyy")}
              aria-selected={isSelected}
              aria-current={isToday ? "date" : undefined}
              onClick={() => onSelect(iso(day))}
              className={cn(
                "mx-auto flex h-9 w-9 items-center justify-center rounded-full text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
                off && "cursor-not-allowed text-[#C9C5D6]",
                !off && !inMonth && "text-[#9A97A8]",
                !off && !isSelected && "hover:bg-[#F1EBFF]",
                isToday && !isSelected && "border border-[#4817C2] font-semibold text-[#4817C2]",
                isSelected && "bg-[#4817C2] font-semibold text-white hover:bg-[#39109F]",
              )}
            >
              {format(day, "d")}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** A date field that opens the calendar in a popover; closes on a pick, on Escape and on a click outside. */
export function SetupDatePicker({
  id,
  value,
  onChange,
  min,
  placeholder = "Select date",
  invalid,
  ariaLabel,
}: {
  id: string;
  value: string;
  onChange: (iso: string) => void;
  min?: string;
  placeholder?: string;
  invalid?: boolean;
  ariaLabel?: string;
}) {
  const [open, setOpen] = React.useState(false);
  const rootRef = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <div ref={rootRef} className="relative">
      <button
        id={id}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-label={ariaLabel}
        onClick={() => setOpen((o) => !o)}
        className={cn(
          "flex h-11 w-full items-center justify-between gap-2 rounded-lg border bg-white px-3 text-left text-[15px] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]/30",
          invalid ? "border-[#C62828]" : "border-[#E5E1EF] hover:border-[#4817C2]/50",
          open && "border-[#4817C2] ring-2 ring-[#4817C2]/20",
          !value && "text-[#9A97A8]",
        )}
      >
        <span>{value ? format(parseISO(value), "dd MMM yyyy") : placeholder}</span>
        <CalendarDays className="h-4 w-4 shrink-0 text-[#4817C2]" aria-hidden="true" />
      </button>
      {open && (
        <div role="dialog" aria-label="Choose a date" className="absolute left-0 z-50 mt-1 rounded-xl border border-[#E5E1EF] bg-white p-3 shadow-[0_10px_30px_rgba(72,23,194,0.14)]">
          <SetupCalendar
            autoFocus
            value={value}
            min={min}
            onSelect={(d) => {
              onChange(d);
              setOpen(false);
            }}
          />
        </div>
      )}
    </div>
  );
}
