"use client";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { DayScheduleCard } from "@/features/operating-hours/components/day-schedule-card";
import { DISPLAY_ORDER } from "@/features/operating-hours/constants";
import type { OperatingDay } from "@/features/operating-hours/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";

export interface OverrideEntry {
  active: boolean;
  days: OperatingDay[];
  errors: Partial<Record<number, string>>;
}

export function PlayingAreaOverrides({
  facilitySports,
  playingAreas,
  sports,
  overrides,
  onCustomize,
  onUseFacilityHours,
  onDayChange,
}: {
  facilitySports: FacilitySport[];
  playingAreas: PlayingArea[];
  sports: Sport[];
  overrides: Record<string, OverrideEntry>;
  onCustomize: (playingAreaId: string) => void;
  onUseFacilityHours: (playingAreaId: string) => void;
  onDayChange: (playingAreaId: string, day: OperatingDay) => void;
}) {
  return (
    <div className="space-y-5">
      <div>
        <h3 className="text-sm font-semibold">Customize individual court/turf hours</h3>
        <p className="text-xs text-muted-foreground">
          By default, all courts and turfs use the facility hours.
        </p>
      </div>

      {facilitySports.map((facilitySport) => {
        const sport = sports.find((s) => s.id === facilitySport.sportId);
        const areas = playingAreas.filter((a) => a.facilitySportId === facilitySport.id);
        if (areas.length === 0) return null;

        return (
          <div key={facilitySport.id} className="space-y-2">
            <h4 className="text-xs font-semibold text-muted-foreground">{sport?.name ?? "Sport"}</h4>
            <div className="space-y-2">
              {areas.map((area) => {
                const override = overrides[area.id];
                const isCustomized = override?.active ?? false;

                return (
                  <Card key={area.id} className="space-y-3 p-4">
                    <div className="flex items-center justify-between gap-3">
                      <span className="text-sm font-medium">{area.name}</span>
                      {isCustomized ? (
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          className="h-9 px-2 text-xs"
                          onClick={() => onUseFacilityHours(area.id)}
                        >
                          Use facility hours
                        </Button>
                      ) : (
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          className="h-9 px-2 text-xs"
                          onClick={() => onCustomize(area.id)}
                        >
                          Customize
                        </Button>
                      )}
                    </div>
                    {!isCustomized && (
                      <p className="text-xs text-muted-foreground">Uses facility hours ✓</p>
                    )}
                    {isCustomized && override && (
                      <div className="space-y-2">
                        {DISPLAY_ORDER.map((dow) => {
                          const day = override.days.find((d) => d.dayOfWeek === dow);
                          if (!day) return null;
                          return (
                            <DayScheduleCard
                              key={dow}
                              day={day}
                              error={override.errors[dow]}
                              onChange={(next) => onDayChange(area.id, next)}
                              onCopyRequest={() => {}}
                              showCopy={false}
                            />
                          );
                        })}
                      </div>
                    )}
                  </Card>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}