import type { Metadata } from "next";
import { CategoriesPage } from "@/features/inventory/components/categories-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Categories — ${APP_NAME}` };

export default function Page() {
  return <CategoriesPage />;
}
