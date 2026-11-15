import type { Metadata } from "next";
import { PlansPage } from "@/features/plans/components/plans-page";

export const metadata: Metadata = {
  title: `Plans`,
};

export default function Page() {
  return <PlansPage />;
}
