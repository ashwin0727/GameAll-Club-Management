import type { Metadata } from "next";
import { AddStaffPage } from "@/features/staff/components/add-staff-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Add Staff — ${APP_NAME}` };

export default function Page() {
  return <AddStaffPage />;
}
