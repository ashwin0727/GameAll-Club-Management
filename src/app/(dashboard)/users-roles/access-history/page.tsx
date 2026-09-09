import type { Metadata } from "next";
import { AccessHistoryPage } from "@/features/staff/components/access-history-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Access History — ${APP_NAME}` };

export default function Page() {
  return <AccessHistoryPage />;
}
