import type { Metadata } from "next";
import { SettingsPage } from "@/features/profile/components/settings-page";

export const metadata: Metadata = {
  title: `Settings`,
};

export default function SettingsRoutePage() {
  return <SettingsPage />;
}
