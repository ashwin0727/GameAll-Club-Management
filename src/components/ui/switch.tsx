"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

export interface SwitchProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "onChange" | "role" | "aria-checked"> {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
}

/** An on/off toggle. A real button with role="switch", so it works with the keyboard and screen readers. */
export const Switch = React.forwardRef<HTMLButtonElement, SwitchProps>(({ checked, onCheckedChange, className, disabled, ...props }, ref) => (
  <button
    ref={ref}
    type="button"
    role="switch"
    aria-checked={checked}
    disabled={disabled}
    onClick={() => onCheckedChange(!checked)}
    className={cn(
      "relative inline-flex h-6 w-11 shrink-0 items-center rounded-full border border-transparent transition-colors",
      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
      "disabled:cursor-not-allowed disabled:opacity-50",
      checked ? "bg-primary" : "bg-input",
      className,
    )}
    {...props}
  >
    <span aria-hidden className={cn("pointer-events-none block h-5 w-5 rounded-full bg-background shadow transition-transform", checked ? "translate-x-5" : "translate-x-0.5")} />
  </button>
));
Switch.displayName = "Switch";
