import type { Metadata } from "next";
import { SupportPage } from "@/features/profile/components/support-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Help & Support — ${APP_NAME}`,
};

export default function HelpPage() {
  return <SupportPage />;
}
