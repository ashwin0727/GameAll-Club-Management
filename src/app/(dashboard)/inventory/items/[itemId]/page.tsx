import type { Metadata } from "next";
import { ItemDetailsPage } from "@/features/inventory/components/item-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Item — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ itemId: string }> }) {
  const { itemId } = await params;
  return <ItemDetailsPage itemId={itemId} />;
}
