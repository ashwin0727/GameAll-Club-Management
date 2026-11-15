import type { Metadata } from "next";
import { PricingPage } from "@/features/plans/components/pricing-page";

export const metadata: Metadata = {
  title: `Pricing`,
  description: "Two simple plans for your club. Start with a free trial.",
};

export default function Page() {
  return <PricingPage />;
}
