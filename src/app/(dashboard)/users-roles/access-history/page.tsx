import type { Metadata } from "next";
import { AccessHistoryPage } from "@/features/staff/components/access-history-page";

export const metadata: Metadata = { title: `Access History` };

export default function Page() {
  return <AccessHistoryPage />;
}
