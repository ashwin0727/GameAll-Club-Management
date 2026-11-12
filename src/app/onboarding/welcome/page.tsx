import type { Metadata } from "next";
import { FacilityWelcome } from "@/features/onboarding/components/facility-welcome";
import { PRODUCT_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Set Up Your Facility — ${PRODUCT_NAME}`,
};

export default function FacilityWelcomePage() {
  return <FacilityWelcome />;
}
