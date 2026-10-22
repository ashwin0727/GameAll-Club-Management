import type { Metadata } from "next";
import { FacilityDetailsPage } from "@/features/profile/components/facility-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Manage Facility Details — ${APP_NAME}`,
};

export default function FacilityPage() {
  return <FacilityDetailsPage />;
}
