import type { Metadata } from "next";
import { PlansPage } from "@/features/plans/components/plans-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Plans — ${APP_NAME}`,
};

export default function Page() {
  return <PlansPage />;
}
