"use client";

import * as React from "react";
import { Eye, EyeOff } from "lucide-react";
import { Input, type InputProps } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { FieldError } from "@/features/auth/components/text-field";

export interface PasswordInputProps extends Omit<InputProps, "type"> {
  label: string;
  error?: string;
  hint?: string;
  id: string;
}

/**
 * Password control with a reveal toggle. Always starts masked; the toggle is a
 * real button so it is reachable by keyboard, and its label announces the
 * action rather than the current state.
 */
export const PasswordInput = React.forwardRef<HTMLInputElement, PasswordInputProps>(
  ({ label, error, hint, id, className, ...props }, ref) => {
    const [visible, setVisible] = React.useState(false);
    const errorId = `${id}-error`;
    const hintId = `${id}-hint`;
    const describedBy = [error ? errorId : null, hint ? hintId : null].filter(Boolean).join(" ");

    return (
      <div className="space-y-2">
        <Label htmlFor={id}>{label}</Label>
        <div className="relative">
          <Input
            id={id}
            ref={ref}
            type={visible ? "text" : "password"}
            aria-invalid={error ? true : undefined}
            aria-describedby={describedBy || undefined}
            className={cn(
              "h-11 bg-secondary/60 pr-12 text-base sm:text-sm",
              error && "border-destructive focus-visible:ring-destructive",
              className,
            )}
            {...props}
          />
          <button
            type="button"
            onClick={() => setVisible((current) => !current)}
            // Excluded from the tab order of the form's happy path, but still
            // operable — screen-reader and keyboard users reach it via the
            // control group without it interrupting field-to-field flow.
            className="absolute inset-y-0 right-0 flex w-11 items-center justify-center rounded-r-md text-muted-foreground outline-none transition-colors hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
            aria-label={visible ? "Hide password" : "Show password"}
            aria-pressed={visible}
          >
            {visible ? (
              <EyeOff className="h-4 w-4" aria-hidden="true" />
            ) : (
              <Eye className="h-4 w-4" aria-hidden="true" />
            )}
          </button>
        </div>
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
PasswordInput.displayName = "PasswordInput";