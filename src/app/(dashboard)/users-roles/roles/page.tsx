import type { Metadata } from "next";
import { RolesPage } from "@/features/staff/components/roles-page";

export const metadata: Metadata = { title: `Roles & Permissions` };

export default function Page() {
  return <RolesPage />;
}
