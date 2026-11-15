import type { Metadata } from "next";
import { BulkMembersSuccessPage } from "@/features/bulk-upload/components/bulk-members-success-page";

export const metadata: Metadata = { title: `Members Added` };

export default function Page() {
  return <BulkMembersSuccessPage />;
}
