import type { Metadata } from "next";
import { ItemDetailsPage } from "@/features/inventory/components/item-details-page";

export const metadata: Metadata = { title: `Item` };

export default async function Page({ params }: { params: Promise<{ itemId: string }> }) {
  const { itemId } = await params;
  return <ItemDetailsPage itemId={itemId} />;
}
