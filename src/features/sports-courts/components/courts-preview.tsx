"use client";

import { Eye, LockKeyhole, Pencil, ShowerHead, Snowflake, Trash2 } from "lucide-react";
import { lightingLabel } from "@/features/courts-setup/constants";
import type { CourtDraft } from "@/features/courts-setup/court-draft";
import type { CourtAmenity } from "@/features/courts-setup/types";
import { CardHeading, SetupCard } from "@/features/onboarding/components/setup-fields";
import type { SelectedSport } from "@/features/sports-courts/components/courts-config";
import { useContainerWide } from "@/features/sports-courts/use-container-wide";
import { cn } from "@/lib/utils";

const AMENITY_ICON: Record<CourtAmenity, { icon: typeof Snowflake; label: string }> = {
  ac: { icon: Snowflake, label: "AC" },
  shower: { icon: ShowerHead, label: "Shower" },
  locker: { icon: LockKeyhole, label: "Locker" },
};

/** The table layout needs about this much room; narrower than that each court is a card (decided from the card's own width). */
const TABLE_MIN_WIDTH = 720;
const GRID_WIDE = "grid grid-cols-[22px_minmax(0,1.6fr)_minmax(0,1.2fr)_minmax(0,0.9fr)_minmax(0,1.1fr)_minmax(0,1fr)_minmax(0,1fr)_76px] items-center gap-x-3 gap-y-2";
const GRID_NARROW = "grid grid-cols-2 gap-x-3 gap-y-2";

/** "Preview of Courts": every configured court across the selected sports, with edit and remove. */
export function CourtsPreview({
  sports,
  drafts,
  onEdit,
  onRemove,
}: {
  sports: SelectedSport[];
  drafts: CourtDraft[];
  onEdit: (court: CourtDraft) => void;
  onRemove: (courtId: string) => void;
}) {
  const [ref, wide] = useContainerWide(TABLE_MIN_WIDTH);
  const grid = wide ? GRID_WIDE : GRID_NARROW;
  const rows = sports.flatMap((s) => drafts.filter((d) => d.sportId === s.id).map((d) => ({ court: d, sport: s })));

  return (
    <SetupCard className="p-4 sm:p-4">
      <CardHeading icon={<Eye className="h-7 w-7" aria-hidden="true" />} title={`Preview of Courts (${rows.length})`} description="All configured courts across selected sports." />

      {rows.length === 0 ? (
        <p className="rounded-xl border border-dashed border-[#E5E1EF] p-6 text-center text-sm text-[#666666]">Courts you add will appear here.</p>
      ) : (
        <div ref={ref} className="min-w-0">
          {wide && (
          <div className={cn(GRID_WIDE, "mb-1 rounded-lg bg-[#F7F5FB] px-2 py-2 text-xs font-semibold")} aria-hidden="true">
            <span>#</span>
            <span>Court Name</span>
            <span>Sport</span>
            <span>Type</span>
            <span>Surface</span>
            <span>Lighting</span>
            <span>Amenities</span>
            <span className="text-right">Actions</span>
          </div>
          )}
          <ul>
            {rows.map(({ court, sport }, i) => (
              <li key={court.id} className={cn(grid, "border-b border-[#EFECF6] px-2 py-3 text-sm last:border-b-0")}>
                {wide && <span>{i + 1}</span>}
                <span className={cn("font-medium", !wide && "col-span-2")}>{court.name}</span>
                <span className="flex items-center gap-2">
                  <span aria-hidden="true">{sport.icon}</span>
                  {sport.name}
                </span>
                <span>
                  <span className={cn("inline-block rounded-full px-3 py-0.5 text-xs font-semibold", court.type === "INDOOR" ? "bg-[#EDE7FF] text-[#4817C2]" : "bg-[#DCFCE7] text-[#2E7D32]")}>
                    {court.type === "INDOOR" ? "Indoor" : "Outdoor"}
                  </span>
                </span>
                <span>{court.surface}</span>
                <span>{lightingLabel(court.lighting || undefined)}</span>
                <span className="flex items-center gap-2 text-[#171717]">
                  {court.amenities.length === 0 ? (
                    <span className="text-[#9A97A8]">–</span>
                  ) : (
                    court.amenities.map((a) => {
                      const { icon: Icon, label } = AMENITY_ICON[a];
                      return (
                        <span key={a} title={label} className="inline-flex">
                          <Icon className="h-4 w-4" aria-hidden="true" />
                          <span className="sr-only">{label}</span>
                        </span>
                      );
                    })
                  )}
                </span>
                <span className={cn("flex justify-end gap-2", !wide && "col-span-2")}>
                  <button
                    type="button"
                    aria-label={`Edit ${court.name}`}
                    onClick={() => onEdit(court)}
                    className="flex h-8 w-8 items-center justify-center rounded-lg border border-[#E5E1EF] bg-white hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
                  >
                    <Pencil className="h-3.5 w-3.5" aria-hidden="true" />
                  </button>
                  <button
                    type="button"
                    aria-label={`Remove ${court.name} from the preview`}
                    onClick={() => onRemove(court.id)}
                    className="flex h-8 w-8 items-center justify-center rounded-lg border border-[#F5B5B0] bg-[#FDECEA] text-[#C62828] hover:bg-[#FADBD8] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#C62828]"
                  >
                    <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                  </button>
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </SetupCard>
  );
}
