import type { Metadata } from "next";
import { RoleEditorPage } from "@/features/staff/components/role-editor-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Create Role — ${APP_NAME}` };

export default function Page() {
  return <RoleEditorPage mode="create" />;
}
