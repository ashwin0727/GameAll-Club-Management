"use client";

import * as React from "react";
import { AlertCircle } from "lucide-react";
import { Input, type InputProps } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

export interface TextFieldProps extends InputProps {
  label: string;
  /** Inline validation message. Its presence is what marks the field invalid. */
  error?: string;
  hint?: string;
  id: string;
}

/**
 * Label + control + message, wired for assistive tech: the message is announced
 * through `aria-describedby`, invalidity through `aria-invalid`, and the error
 * carries an icon so the state is never signalled by colour alone.
 *
 * `h-11` keeps every control at a 44px touch target on mobile.
 */
export const TextField = React.forwardRef<HTMLInputElement, TextFieldProps>(
  ({ label, error, hint, id, className, ...props }, ref) => {
    const errorId = `${id}-error`;
    const hintId = `${id}-hint`;
    const describedBy = [error ? errorId : null, hint ? hintId : null].filter(Boolean).join(" ");

    return (
      <div className="space-y-2">
        <Label htmlFor={id}>{label}</Label>
        <Input
          id={id}
          ref={ref}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy || undefined}
          className={cn(
            "h-11 bg-secondary/60 text-base sm:text-sm",
            error && "border-destructive focus-visible:ring-destructive",
            className,
          )}
          {...props}
        />
        {hint && !error && (
          <p id={hintId} className="text-xs text-muted-foreground">
            {hint}
          </p>
        )}
        {error && <FieldError id={errorId}>{error}</FieldError>}
      </div>
    );
  },
);
TextField.displayName = "TextField";

export function FieldError({ id, children }: { id?: string; children: React.ReactNode }) {
  return (
    <p id={id} className="flex items-start gap-1.5 text-xs font-medium text-destructive">
      <AlertCircle className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      <span>{children}</span>
    </p>
  );
}