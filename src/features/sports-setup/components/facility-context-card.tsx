import { Building2 } from "lucide-react";
import { Card } from "@/components/ui/card";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";
import type { Facility } from "@/features/onboarding/types";

export function FacilityContextCard({ facility }: { facility: Facility }) {
  const typeLabel =
    FACILITY_TYPE_OPTIONS.find((option) => option.value === facility.type)?.label ?? facility.type;

  return (
    <Card className="p-5">
      <div className="flex items-center gap-4">
        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
          <Building2 className="h-6 w-6" aria-hidden="true" />
        </div>
        <div className="min-w-0">
          <p className="truncate text-base font-semibold text-foreground">{facility.name}</p>
          <p className="truncate text-sm text-muted-foreground">{facility.address.city}</p>
          <p className="text-xs text-muted-foreground">Facility Type: {typeLabel}</p>
        </div>
      </div>
    </Card>
  );
}