"use client";

import { Loader2 } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export interface SubmitButtonProps extends ButtonProps {
  /** Idle label. */
  children: React.ReactNode;
  /** Label while the request is in flight, e.g. "Creating account…". */
  pendingLabel: string;
  pending?: boolean;
}

/**
 * Primary action for every auth form. While pending it swaps its label, shows a
 * spinner and disables itself, which is what prevents a double submit.
 */
export function SubmitButton({
  children,
  pendingLabel,
  pending = false,
  disabled,
  className,
  ...props
}: SubmitButtonProps) {
  return (
    <Button
      type="submit"
      disabled={pending || disabled}
      aria-busy={pending || undefined}
      className={cn("h-11 w-full text-sm font-semibold", className)}
      {...props}
    >
      {pending && <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />}
      {pending ? pendingLabel : children}
    </Button>
  );
}