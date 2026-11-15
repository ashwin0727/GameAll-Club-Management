import type { Metadata } from "next";
import { BulkStudentsSuccessPage } from "@/features/bulk-upload/components/bulk-students-success-page";

export const metadata: Metadata = { title: `Students Added` };

export default function Page() {
  return <BulkStudentsSuccessPage />;
}
