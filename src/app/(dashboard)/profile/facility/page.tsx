import type { Metadata } from "next";
import { FacilityDetailsPage } from "@/features/profile/components/facility-details-page";

export const metadata: Metadata = {
  title: `Manage Facility Details`,
};

export default function FacilityPage() {
  return <FacilityDetailsPage />;
}
