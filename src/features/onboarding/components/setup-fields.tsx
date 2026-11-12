"use client";

import * as React from "react";
import { AlertCircle, Info } from "lucide-react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { setupFontClass } from "@/features/onboarding/components/onboarding-shell";
import { cn } from "@/lib/utils";

/** Light-mode form pieces for the facility-setup screens (colours from the GameAll setup palette). */

export const fieldControl =
  "h-11 w-full rounded-lg border border-[#E5E1EF] bg-white px-3 text-[15px] font-normal text-[#171717] placeholder:text-[#9A97A8] " +
  "transition-colors focus:border-[#4817C2] focus:outline-none focus:ring-2 focus:ring-[#4817C2]/20 disabled:bg-[#F7F5FB] disabled:text-[#666666]";

export function SetupCard({ className, children }: { className?: string; children: React.ReactNode }) {
  return <section className={cn("rounded-2xl border border-[#E5E1EF] bg-white p-5 sm:p-6", className)}>{children}</section>;
}

export function CardHeading({ icon, title, description, action }: { icon?: React.ReactNode; title: string; description?: string; action?: React.ReactNode }) {
  return (
    <div className="mb-4 flex items-start justify-between gap-3">
      <div className="flex items-start gap-3">
        {icon && <span className="mt-0.5 text-[#4817C2]">{icon}</span>}
        <div>
          <h2 className="text-lg font-semibold leading-tight">{title}</h2>
          {description && <p className="mt-0.5 text-sm font-normal text-[#666666]">{description}</p>}
        </div>
      </div>
      {action}
    </div>
  );
}

export function FieldError({ id, children }: { id?: string; children: React.ReactNode }) {
  return (
    <p id={id} role="alert" className="mt-1.5 flex items-start gap-1.5 text-xs font-medium text-[#C62828]">
      <AlertCircle className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      {children}
    </p>
  );
}

/** Label (600) + control + optional hint / error, wired with aria. */
export function Field({
  id,
  label,
  optional,
  required,
  hint,
  error,
  className,
  children,
}: {
  id: string;
  label: string;
  optional?: boolean;
  required?: boolean;
  hint?: string;
  error?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={className}>
      <label htmlFor={id} className="mb-1.5 block whitespace-nowrap text-sm font-semibold leading-5">
        {label}
        {required && (
          <span className="ml-0.5 text-[#C62828]" aria-hidden="true">
            *
          </span>
        )}
        {optional && <span className="ml-1 text-xs font-normal text-[#666666]">(Optional)</span>}
      </label>
      {children}
      {hint && !error && <p className="mt-1.5 text-xs font-normal text-[#666666]">{hint}</p>}
      {error && <FieldError id={`${id}-error`}>{error}</FieldError>}
    </div>
  );
}

export const SetupInput = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement> & { invalid?: boolean; leading?: React.ReactNode }>(
  ({ className, invalid, leading, id, ...props }, ref) => (
    <div className="relative">
      {leading && <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[#666666]">{leading}</span>}
      <input
        ref={ref}
        id={id}
        aria-invalid={invalid || undefined}
        aria-describedby={invalid ? `${id}-error` : undefined}
        className={cn(fieldControl, leading && "pl-10", invalid && "border-[#C62828] focus:border-[#C62828] focus:ring-[#C62828]/20", className)}
        {...props}
      />
    </div>
  ),
);
SetupInput.displayName = "SetupInput";

export const SetupTextarea = React.forwardRef<HTMLTextAreaElement, React.TextareaHTMLAttributes<HTMLTextAreaElement> & { invalid?: boolean }>(
  ({ className, invalid, id, ...props }, ref) => (
    <textarea
      ref={ref}
      id={id}
      aria-invalid={invalid || undefined}
      aria-describedby={invalid ? `${id}-error` : undefined}
      className={cn(fieldControl, "h-24 resize-none py-2.5", invalid && "border-[#C62828] focus:border-[#C62828] focus:ring-[#C62828]/20", className)}
      {...props}
    />
  ),
);
SetupTextarea.displayName = "SetupTextarea";

/**
 * A styled dropdown in the setup look (not the browser's native list): rounded trigger with a purple focus/open outline, and a
 * rounded white menu with a soft border whose chosen row is highlighted in the active purple.
 */
export function SetupSelect({
  id,
  value,
  onChange,
  onBlur,
  options,
  placeholder,
  invalid,
  ariaLabel,
  icon,
  disabled,
}: {
  id: string;
  value: string;
  onChange: (value: string) => void;
  onBlur?: () => void;
  options: readonly { value: string; label: string }[];
  placeholder?: string;
  invalid?: boolean;
  /** For a dropdown with no visible label of its own (a cell in a table row). */
  ariaLabel?: string;
  /** A small icon shown before the value (e.g. a clock for a time). */
  icon?: React.ReactNode;
  disabled?: boolean;
}) {
  return (
    <Select value={value || undefined} onValueChange={onChange} disabled={disabled}>
      <SelectTrigger
        id={id}
        aria-label={ariaLabel}
        onBlur={onBlur}
        aria-invalid={invalid || undefined}
        aria-describedby={invalid ? `${id}-error` : undefined}
        className={cn(
          "h-11 rounded-lg border-[#E5E1EF] bg-white px-3 text-[15px] font-normal text-[#171717] shadow-none hover:border-[#4817C2]/50",
          "focus:border-[#4817C2] focus:ring-2 focus:ring-[#4817C2]/20 data-[state=open]:border-[#4817C2] data-[state=open]:ring-2 data-[state=open]:ring-[#4817C2]/20",
          "data-[placeholder]:text-[#9A97A8] [&>svg]:text-[#171717] [&>svg]:opacity-100",
          invalid && "border-[#C62828] focus:border-[#C62828] focus:ring-[#C62828]/20",
        )}
      >
        {icon ? (
          <span className="flex min-w-0 items-center gap-2">
            <span className="shrink-0 text-[#666666]">{icon}</span>
            <SelectValue placeholder={placeholder} />
          </span>
        ) : (
          <SelectValue placeholder={placeholder} />
        )}
      </SelectTrigger>
      <SelectContent
        className={cn(
          setupFontClass,
          "max-h-[min(18rem,var(--radix-select-content-available-height))] rounded-xl border border-[#E5E1EF] bg-white p-0 text-[#171717] shadow-[0_10px_30px_rgba(72,23,194,0.14)]",
        )}
      >
        {options.map((o) => (
          <SelectItem
            key={o.value}
            value={o.value}
            className="rounded-lg px-3 py-2.5 text-[15px] font-normal focus:bg-[#F7F5FB] focus:text-[#171717] data-[state=checked]:bg-[#F1EBFF] data-[state=checked]:font-semibold data-[state=checked]:text-[#4817C2] [&_svg]:text-[#4817C2]"
          >
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

/** Two-or-more option pill group (Owned / Leased, Indoor / Outdoor). */
export function Segmented<T extends string>({
  label,
  value,
  onChange,
  options,
  invalid,
}: {
  label: string;
  value: T | undefined;
  onChange: (value: T) => void;
  options: readonly { value: T; label: string }[];
  invalid?: boolean;
}) {
  const n = options.length;
  const index = options.findIndex((o) => o.value === value);
  return (
    <div role="radiogroup" aria-label={label} className={cn("relative grid h-11 rounded-lg border bg-white", invalid ? "border-[#C62828]" : "border-[#E5E1EF]")} style={{ gridTemplateColumns: `repeat(${n}, 1fr)` }}>
      {/* One highlight that sits exactly on the control's border and slides to the chosen option, so there is only ever a single outline. */}
      {index >= 0 && (
        <span
          aria-hidden="true"
          className="pointer-events-none absolute -bottom-px -top-px rounded-lg border-[1.5px] border-[#4817C2] bg-[#F1EBFF] transition-[left] duration-150 ease-out"
          style={{ width: `calc(${100 / n}% + 2px)`, left: `calc(${(index * 100) / n}% - 1px)` }}
        />
      )}
      {options.map((o) => {
        const on = value === o.value;
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={on}
            onClick={() => onChange(o.value)}
            className={cn(
              "relative z-10 flex items-center justify-center gap-2 rounded-lg text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
              on ? "text-[#4817C2]" : "text-[#171717] hover:text-[#4817C2]",
            )}
          >
            {on && <span className="flex h-4 w-4 items-center justify-center rounded-full bg-[#4817C2] text-[10px] text-white">✓</span>}
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

/** A checkbox row with an optional "i" hint pinned to the right edge, so every row lines up whatever the label length. */
export function CheckRow({ id, checked, onChange, label, hint }: { id: string; checked: boolean; onChange: (next: boolean) => void; label: string; hint?: string }) {
  return (
    <div className="flex min-h-6 items-center gap-2.5">
      <input id={id} type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="h-5 w-5 shrink-0 cursor-pointer rounded accent-[#4817C2]" />
      <label htmlFor={id} className="flex-1 cursor-pointer text-sm font-medium leading-5">
        {label}
      </label>
      {hint && (
        <span title={hint} className="ml-auto shrink-0 text-[#666666]">
          <Info className="h-4 w-4" aria-hidden="true" />
          <span className="sr-only">{hint}</span>
        </span>
      )}
    </div>
  );
}
