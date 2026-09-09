import type { Metadata } from "next";
import { RoleEditorPage } from "@/features/staff/components/role-editor-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Edit Role — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ roleId: string }> }) {
  const { roleId } = await params;
  return <RoleEditorPage mode="edit" roleId={roleId} />;
}
