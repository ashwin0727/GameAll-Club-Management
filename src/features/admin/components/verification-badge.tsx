import { CheckCircle2, Clock, XCircle } from "lucide-react";
import type { PayoutVerification } from "@/features/admin/service";
import { cn } from "@/lib/utils";

const STYLE: Record<PayoutVerification, { label: string; className: string; icon: typeof Clock }> = {
  VERIFIED: { label: "Verified", className: "bg-primary/10 text-primary", icon: CheckCircle2 },
  PENDING: { label: "Pending", className: "bg-warning/15 text-warning", icon: Clock },
  REJECTED: { label: "Rejected", className: "bg-destructive/10 text-destructive", icon: XCircle },
};

export function VerificationBadge({ status }: { status: PayoutVerification }) {
  const s = STYLE[status];
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold", s.className)}>
      <s.icon className="h-3.5 w-3.5" aria-hidden />
      {s.label}
    </span>
  );
}
