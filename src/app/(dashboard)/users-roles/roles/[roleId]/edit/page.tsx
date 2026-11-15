import type { Metadata } from "next";
import { RoleEditorPage } from "@/features/staff/components/role-editor-page";

export const metadata: Metadata = { title: `Edit Role` };

export default async function Page({ params }: { params: Promise<{ roleId: string }> }) {
  const { roleId } = await params;
  return <RoleEditorPage mode="edit" roleId={roleId} />;
}
