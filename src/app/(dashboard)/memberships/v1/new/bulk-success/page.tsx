import type { Metadata } from "next";
import { BulkMembersSuccessPage } from "@/features/bulk-upload/components/bulk-members-success-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Members Added — ${APP_NAME}` };

export default function Page() {
  return <BulkMembersSuccessPage />;
}
