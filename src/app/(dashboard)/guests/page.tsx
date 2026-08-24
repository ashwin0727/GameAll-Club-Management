import type { Metadata } from "next";
import { GuestList } from "@/features/guests/components/guest-list";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Guest Players — ${APP_NAME}`,
};

export default function GuestsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Guest Players</h1>
        <p className="text-sm text-muted-foreground">Manage walk-in players and their booking history.</p>
      </div>
      <GuestList />
    </div>
  );
}