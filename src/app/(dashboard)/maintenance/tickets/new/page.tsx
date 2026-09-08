import type { Metadata } from "next";
import { CreateTicketWizard } from "@/features/maintenance/components/create-ticket-wizard";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Create Maintenance Ticket — ${APP_NAME}`,
};

export default function NewTicketPage() {
  return <CreateTicketWizard />;
}
