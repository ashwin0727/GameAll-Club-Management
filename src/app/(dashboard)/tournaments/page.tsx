import type { Metadata } from "next";
import { TournamentManagementPage } from "@/features/tournaments/components/tournament-management-page";

export const metadata: Metadata = { title: `Tournament Management` };

export default function Page() {
  return <TournamentManagementPage />;
}
