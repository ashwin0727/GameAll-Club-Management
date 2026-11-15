import type { Metadata } from "next";
import { RoleEditorPage } from "@/features/staff/components/role-editor-page";

export const metadata: Metadata = { title: `Create Role` };

export default function Page() {
  return <RoleEditorPage mode="create" />;
}
