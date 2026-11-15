import type { Metadata } from "next";
import { SupportPage } from "@/features/profile/components/support-page";

export const metadata: Metadata = {
  title: `Help & Support`,
};

export default function HelpPage() {
  return <SupportPage />;
}
