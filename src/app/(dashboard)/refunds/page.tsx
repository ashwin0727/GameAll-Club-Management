import type { Metadata } from "next";
import { RefundsPanel } from "@/features/refunds/components/refunds-panel";

export const metadata: Metadata = {
  title: `Refunds`,
};

export default function RefundsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Refunds</h1>
        <p className="text-sm text-muted-foreground">Resolve payments that couldn&apos;t be confirmed, and track every refund.</p>
      </div>
      <RefundsPanel />
    </div>
  );
}