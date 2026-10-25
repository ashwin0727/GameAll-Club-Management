import type { Metadata } from "next";
import { PricingPage } from "@/features/plans/components/pricing-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Pricing — ${APP_NAME}`,
  description: "Two simple plans for your club. Start with a free trial.",
};

export default function Page() {
  return <PricingPage />;
}
