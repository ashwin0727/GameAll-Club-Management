import type { Metadata } from "next";
import { SettingsPage } from "@/features/profile/components/settings-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Settings — ${APP_NAME}`,
};

export default function SettingsRoutePage() {
  return <SettingsPage />;
}
