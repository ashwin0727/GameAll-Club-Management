import type { Metadata } from "next";
import { StaffPage } from "@/features/staff/components/staff-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Staff — ${APP_NAME}` };

export default function Page() {
  return <StaffPage />;
}
