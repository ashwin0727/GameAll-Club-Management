import type { Metadata } from "next";
import { RolesPage } from "@/features/staff/components/roles-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Roles & Permissions — ${APP_NAME}` };

export default function Page() {
  return <RolesPage />;
}
