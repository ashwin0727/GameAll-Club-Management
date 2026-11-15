import type { Metadata } from "next";
import { StaffPage } from "@/features/staff/components/staff-page";

export const metadata: Metadata = { title: `Staff` };

export default function Page() {
  return <StaffPage />;
}
