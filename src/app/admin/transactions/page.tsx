import type { Metadata } from "next";
import { AdminTransactionsPage } from "@/features/admin/components/admin-transactions-page";

export const metadata: Metadata = { title: "Admin — Transactions" };

export default function Page() {
  return <AdminTransactionsPage />;
}
