import type { Metadata } from "next";
import { TicketDetailPage } from "@/features/maintenance/components/ticket-detail-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Maintenance Ticket — ${APP_NAME}`,
};

export default async function Page({ params }: { params: Promise<{ ticketId: string }> }) {
  const { ticketId } = await params;
  return <TicketDetailPage ticketId={ticketId} />;
}
