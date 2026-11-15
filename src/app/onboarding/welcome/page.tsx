import type { Metadata } from "next";
import { FacilityWelcome } from "@/features/onboarding/components/facility-welcome";

export const metadata: Metadata = {
  title: `Set Up Your Facility`,
};

export default function FacilityWelcomePage() {
  return <FacilityWelcome />;
}
