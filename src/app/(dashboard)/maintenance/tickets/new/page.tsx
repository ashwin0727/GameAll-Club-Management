import type { Metadata } from "next";
import { CreateTicketWizard } from "@/features/maintenance/components/create-ticket-wizard";

export const metadata: Metadata = {
  title: `Create Maintenance Ticket`,
};

export default function NewTicketPage() {
  return <CreateTicketWizard />;
}
