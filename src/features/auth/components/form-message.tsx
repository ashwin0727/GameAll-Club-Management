"use client";

import { AlertCircle, CheckCircle2, Info } from "lucide-react";
import { cn } from "@/lib/utils";

type Tone = "error" | "success" | "info";

const TONES: Record<Tone, { className: string; Icon: React.ComponentType<{ className?: string }> }> =
  {
    error: {
      className: "border-destructive/40 bg-destructive/10 text-destructive",
      Icon: AlertCircle,
    },
    success: { className: "border-success/40 bg-success/10 text-success", Icon: CheckCircle2 },
    info: { className: "border-border bg-secondary text-muted-foreground", Icon: Info },
  };

/**
 * Form-level banner for anything not attached to a single field — invalid
 * credentials, a sent email, a network failure.
 *
 * Errors are announced assertively; everything else politely. Inline by design:
 * the flow uses no `alert()` and no floating popovers for validation.
 */
export function FormMessage({
  tone = "error",
  children,
  className,
}: {
  tone?: Tone;
  children: React.ReactNode;
  className?: string;
}) {
  const { className: toneClass, Icon } = TONES[tone];

  return (
    <div
      role={tone === "error" ? "alert" : "status"}
      aria-live={tone === "error" ? "assertive" : "polite"}
      className={cn(
        "flex items-start gap-2.5 rounded-lg border px-3.5 py-3 text-sm",
        toneClass,
        className,
      )}
    >
      <Icon className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
      <div className="leading-relaxed">{children}</div>
    </div>
  );
}