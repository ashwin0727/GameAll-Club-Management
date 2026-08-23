import type { Metadata } from "next";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Pricing — ${PRODUCT_NAME}`,
};

export default function PricingPlaceholderPage() {
  return (
    <div className="space-y-2 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">Pricing — Coming Next</h1>
      <p className="text-sm text-muted-foreground">
        Great work! Next you&apos;ll set up pricing for your courts and turfs. This step is being
        built next.
      </p>
    </div>
  );
}