import { SportCard } from "@/features/sports-setup/components/sport-card";
import type { Sport } from "@/features/sports-setup/types";

export interface SportGridProps {
  sports: Sport[];
  selectedSportIds: string[];
  onToggle: (sportId: string) => void;
}

export function SportGrid({ sports, selectedSportIds, onToggle }: SportGridProps) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {sports.map((sport) => (
        <SportCard
          key={sport.id}
          sport={sport}
          selected={selectedSportIds.includes(sport.id)}
          onToggle={onToggle}
        />
      ))}
    </div>
  );
}