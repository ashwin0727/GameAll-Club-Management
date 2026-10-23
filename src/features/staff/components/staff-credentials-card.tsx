"use client";

import { useState } from "react";
import { Check, Copy, Eye, EyeOff } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * The login a staff member signs in with: the generated @gameall.co email and (optionally) the default password. The
 * password is hidden until the owner chooses to reveal it, and each value has its own Copy button.
 */
export function StaffCredentialsCard({ loginEmail, password }: { loginEmail: string; password?: string | null }) {
  const [reveal, setReveal] = useState(false);
  return (
    <div className="space-y-3 rounded-xl border border-border bg-muted/30 p-4 text-left">
      <CredentialRow label="Login Email" value={loginEmail} />
      {password && <CredentialRow label="Password" value={password} secret reveal={reveal} onToggleReveal={() => setReveal((v) => !v)} />}
    </div>
  );
}

function CredentialRow({
  label,
  value,
  secret,
  reveal,
  onToggleReveal,
}: {
  label: string;
  value: string;
  secret?: boolean;
  reveal?: boolean;
  onToggleReveal?: () => void;
}) {
  const [copied, setCopied] = useState(false);
  const shown = secret && !reveal ? "•".repeat(Math.min(value.length, 14)) : value;
  return (
    <div>
      <p className="text-xs font-medium text-muted-foreground">{label}</p>
      <div className="mt-1 flex items-center justify-between gap-2 rounded-lg border border-border bg-background px-3 py-2">
        <code className="min-w-0 flex-1 break-all text-sm font-medium">{shown}</code>
        <div className="flex shrink-0 items-center gap-1">
          {secret && (
            <Button type="button" size="sm" variant="ghost" className="h-8 w-8 p-0" onClick={onToggleReveal} aria-label={reveal ? "Hide password" : "Show password"}>
              {reveal ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </Button>
          )}
          <Button
            type="button"
            size="sm"
            variant="outline"
            className="h-8"
            onClick={() => {
              void navigator.clipboard?.writeText(value);
              setCopied(true);
              window.setTimeout(() => setCopied(false), 1800);
            }}
          >
            {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
            {copied ? "Copied" : "Copy"}
          </Button>
        </div>
      </div>
    </div>
  );
}
