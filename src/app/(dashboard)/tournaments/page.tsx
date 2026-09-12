import type { Metadata } from "next";
import { TournamentManagementPage } from "@/features/tournaments/components/tournament-management-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Tournament Management — ${APP_NAME}` };

export default function Page() {
  return <TournamentManagementPage />;
}
