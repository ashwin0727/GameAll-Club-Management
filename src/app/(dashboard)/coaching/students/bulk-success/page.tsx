import type { Metadata } from "next";
import { BulkStudentsSuccessPage } from "@/features/bulk-upload/components/bulk-students-success-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Students Added — ${APP_NAME}` };

export default function Page() {
  return <BulkStudentsSuccessPage />;
}
