"use client";

import * as React from "react";
import { ChevronRight, Info, LayoutGrid, Plus, Settings2, Trash2 } from "lucide-react";
import { COURT_AMENITY_OPTIONS, COURT_TYPE_OPTIONS, LIGHTING_OPTIONS, surfaceOptionsFor } from "@/features/courts-setup/constants";
import type { CourtDraft, CourtProblems, CourtSettings } from "@/features/courts-setup/court-draft";
import type { CourtAmenity, LightingType } from "@/features/courts-setup/types";
import { CardHeading, FieldError, SetupCard, SetupInput, SetupSelect } from "@/features/onboarding/components/setup-fields";
import { useContainerWide } from "@/features/sports-courts/use-container-wide";
import { cn } from "@/lib/utils";

export interface SelectedSport {
  id: string;
  name: string;
  code: string;
  icon: string;
}

export type ConfigMode = "court" | "bulk";

/**
 * # | name | type | surface | lighting | amenities | remove. The table layout needs about this much room; narrower than that (a phone, a
 * zoomed-in page, a squeezed panel) each court becomes a card with the same fields stacked in pairs, so nothing is cut off or overlaps.
 */
const TABLE_MIN_WIDTH = 780;
const GRID_WIDE = "grid grid-cols-[22px_minmax(0,1.7fr)_minmax(0,1fr)_minmax(0,1.15fr)_minmax(0,1fr)_minmax(0,2.1fr)_30px] items-start gap-2";
const GRID_NARROW = "grid grid-cols-[repeat(auto-fit,minmax(150px,1fr))] gap-3";

/** Whether the court table is wide enough for its column layout (decided from the table's own width). */
const WideContext = React.createContext(false);

function Cell({ label, required, className, children }: { label: string; required?: boolean; className?: string; children: React.ReactNode }) {
  const wide = React.useContext(WideContext);
  return (
    <div className={className}>
      {!wide && (
        <span className="mb-1 block text-xs font-semibold text-[#666666]">
          {label}
          {required && <span className="ml-0.5 text-[#C62828]">*</span>}
        </span>
      )}
      {children}
    </div>
  );
}

function AmenityChecks({ idPrefix, value, onChange }: { idPrefix: string; value: CourtAmenity[]; onChange: (next: CourtAmenity[]) => void }) {
  const wide = React.useContext(WideContext);
  return (
    <div className={cn("-ml-1 flex h-11 items-center gap-x-1 gap-y-1", wide ? "flex-nowrap" : "flex-wrap")}>
      {COURT_AMENITY_OPTIONS.map((a) => {
        const on = value.includes(a.value);
        return (
          <label
            key={a.value}
            htmlFor={`${idPrefix}-${a.value}`}
            className={cn("flex cursor-pointer items-center gap-1 whitespace-nowrap rounded-md px-1 py-1 text-[13px] font-medium", on && "bg-[#F1EBFF]")}
          >
            <input
              id={`${idPrefix}-${a.value}`}
              type="checkbox"
              checked={on}
              onChange={(e) => onChange(e.target.checked ? [...value, a.value] : value.filter((x) => x !== a.value))}
              className="h-4 w-4 cursor-pointer rounded accent-[#4817C2]"
            />
            {a.label}
          </label>
        );
      })}
    </div>
  );
}

/** A cell that takes the full row when the court is shown as a card. */
function WideAware({ label, required, children }: { label: string; required?: boolean; children: React.ReactNode }) {
  const wide = React.useContext(WideContext);
  return (
    <Cell label={label} required={required} className={wide ? undefined : "col-span-full"}>
      {children}
    </Cell>
  );
}

/** The type / surface / lighting / amenities cells, shared by a court row and the bulk "all courts" row. */
function SettingCells({
  idPrefix,
  sportCode,
  label,
  settings,
  problems,
  onChange,
}: {
  idPrefix: string;
  sportCode: string;
  label: string;
  settings: CourtSettings;
  problems?: { surface?: string; lighting?: string };
  onChange: (patch: Partial<CourtSettings>) => void;
}) {
  const surfaces = surfaceOptionsFor(sportCode);
  const surfaceOptions = (settings.surface && !surfaces.includes(settings.surface) ? [settings.surface, ...surfaces] : surfaces).map((s) => ({ value: s, label: s }));
  return (
    <>
      <Cell label="Court Type" required>
        <SetupSelect id={`${idPrefix}-type`} ariaLabel={`${label} court type`} value={settings.type} onChange={(v) => onChange({ type: v as CourtSettings["type"] })} options={COURT_TYPE_OPTIONS} />
      </Cell>
      <Cell label="Surface Type" required>
        <SetupSelect id={`${idPrefix}-surface`} ariaLabel={`${label} surface type`} value={settings.surface} onChange={(v) => onChange({ surface: v })} options={surfaceOptions} placeholder="Select" invalid={!!problems?.surface} />
        {problems?.surface && <FieldError>{problems.surface}</FieldError>}
      </Cell>
      <Cell label="Lighting" required>
        <SetupSelect id={`${idPrefix}-lighting`} ariaLabel={`${label} lighting`} value={settings.lighting} onChange={(v) => onChange({ lighting: v as LightingType })} options={LIGHTING_OPTIONS} placeholder="Select" invalid={!!problems?.lighting} />
        {problems?.lighting && <FieldError>{problems.lighting}</FieldError>}
      </Cell>
      <WideAware label="Amenities (Optional)">
        <AmenityChecks idPrefix={`${idPrefix}-amenity`} value={settings.amenities} onChange={(amenities) => onChange({ amenities })} />
      </WideAware>
    </>
  );
}

export function CourtsConfig({
  sports,
  drafts,
  activeSportId,
  onActiveSport,
  mode,
  onModeChange,
  onChange,
  onBulk,
  onAdd,
  onRemove,
  problems,
}: {
  sports: SelectedSport[];
  drafts: CourtDraft[];
  activeSportId: string | undefined;
  onActiveSport: (sportId: string) => void;
  mode: ConfigMode;
  onModeChange: (mode: ConfigMode) => void;
  onChange: (courtId: string, patch: Partial<CourtDraft>) => void;
  onBulk: (sportId: string, patch: Partial<CourtSettings>) => void;
  onAdd: (sportId: string) => void;
  onRemove: (courtId: string) => void;
  problems: CourtProblems;
}) {
  const [panelRef, wide] = useContainerWide(TABLE_MIN_WIDTH);
  const grid = wide ? GRID_WIDE : GRID_NARROW;
  const active = sports.find((s) => s.id === activeSportId) ?? sports[0];
  const courts = active ? drafts.filter((d) => d.sportId === active.id) : [];
  const first = courts[0];

  return (
    <SetupCard className="p-4 sm:p-4">
      <CardHeading
        icon={<LayoutGrid className="h-7 w-7" aria-hidden="true" />}
        title="Configure Courts"
        description="Add and manage courts for each selected sport."
        action={
          <div className="flex items-center gap-2">
            <div role="radiogroup" aria-label="How to configure courts" className="flex flex-wrap gap-2">
              {(
                [
                  { value: "court", label: "Configure by Court", icon: Settings2 },
                  { value: "bulk", label: "Bulk (Same for All Courts)", icon: LayoutGrid },
                ] as const
              ).map((m) => (
                <button
                  key={m.value}
                  type="button"
                  role="radio"
                  aria-checked={mode === m.value}
                  onClick={() => onModeChange(m.value)}
                  className={cn(
                    "flex h-9 items-center gap-1.5 rounded-lg border px-3 text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
                    mode === m.value ? "border-[#4817C2] bg-[#F1EBFF] text-[#4817C2]" : "border-[#E5E1EF] bg-white text-[#171717] hover:bg-[#FBFAFE]",
                  )}
                >
                  <m.icon className="h-4 w-4" aria-hidden="true" />
                  {m.label}
                </button>
              ))}
            </div>
            <span title="Configure by Court sets each court on its own. Bulk applies one set of type, surface, lighting and amenities to every court of the sport." className="text-[#666666]">
              <Info className="h-5 w-5" aria-hidden="true" />
              <span className="sr-only">Configure by Court sets each court on its own. Bulk applies one set of settings to every court of the sport.</span>
            </span>
          </div>
        }
      />

      {sports.length === 0 || !active ? (
        <p className="rounded-xl border border-dashed border-[#E5E1EF] p-6 text-center text-sm text-[#666666]">Select at least one sport above to add its courts.</p>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[200px_minmax(0,1fr)]">
          <ul className="flex gap-2 overflow-x-auto pb-1 lg:flex-col lg:overflow-visible lg:pb-0" aria-label="Selected sports">
            {sports.map((s) => {
              const count = drafts.filter((d) => d.sportId === s.id).length;
              const on = s.id === active.id;
              return (
                <li key={s.id} className="shrink-0 lg:shrink">
                  <button
                    type="button"
                    aria-current={on ? "true" : undefined}
                    aria-label={`${s.name} (${count})`}
                    onClick={() => onActiveSport(s.id)}
                    className={cn(
                      "flex h-12 w-full min-w-[150px] items-center gap-3 rounded-xl border px-3 text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
                      on ? "border-[#4817C2] bg-[#F1EBFF]" : "border-[#E5E1EF] bg-white hover:bg-[#FBFAFE]",
                      problems.bySport[s.id] && "border-[#C62828]",
                    )}
                  >
                    <span className="text-xl leading-none" aria-hidden="true">
                      {s.icon}
                    </span>
                    <span className="flex min-w-0 flex-1 items-center gap-2 text-left">
                      <span className="truncate">{s.name}</span>
                      {/* the number of courts, as its own badge so it never runs into the name */}
                      <span
                        aria-hidden="true"
                        className={cn(
                          "inline-flex h-5 min-w-5 shrink-0 items-center justify-center rounded-full px-1 text-xs font-semibold leading-none tabular-nums",
                          on ? "bg-[#4817C2] text-white" : "bg-[#EDE7FF] text-[#4817C2]",
                        )}
                      >
                        {count}
                      </span>
                    </span>
                    <ChevronRight className="h-4 w-4 shrink-0 text-[#171717]" aria-hidden="true" />
                  </button>
                </li>
              );
            })}
          </ul>

          <WideContext.Provider value={wide}>
          <div ref={panelRef} className="min-w-0 rounded-xl border border-[#E5E1EF] p-3">
            <h3 className="mb-3 text-lg font-semibold">
              {active.name} Courts ({courts.length})
            </h3>

            {/* column headings (only when the table layout fits) */}
            {wide && (
            <div className={cn(GRID_WIDE, "mb-2 rounded-lg bg-[#F7F5FB] px-2 py-2 text-xs font-semibold")} aria-hidden="true">
              <span>#</span>
              <span>
                Court Name<span className="text-[#C62828]"> *</span>
              </span>
              <span>
                Court Type<span className="text-[#C62828]"> *</span>
              </span>
              <span>
                Surface Type<span className="text-[#C62828]"> *</span>
              </span>
              <span>
                Lighting<span className="text-[#C62828]"> *</span>
              </span>
              <span>
                Amenities <span className="font-normal text-[#666666]">(Optional)</span>
              </span>
              <span />
            </div>
            )}

            {mode === "bulk" && first && (
              <div className={cn(grid, "mb-2 rounded-lg border border-[#4817C2]/30 bg-[#F8F4FF]", wide ? "px-2 py-2" : "p-3")} data-testid="bulk-row">
                {wide && (
                  <span className="pt-3 text-sm" aria-hidden="true">
                    *
                  </span>
                )}
                <Cell label="Applies to" className={wide ? undefined : "col-span-full"}>
                  <p className="flex h-11 items-center text-sm font-semibold text-[#4817C2]">All {active.name} courts</p>
                </Cell>
                <SettingCells
                  idPrefix={`bulk-${active.id}`}
                  sportCode={active.code}
                  label={`All ${active.name} courts`}
                  settings={first}
                  onChange={(patch) => onBulk(active.id, patch)}
                />
                {wide && <span />}
              </div>
            )}

            <ul className="space-y-2">
              {courts.map((court, index) => {
                const p = problems.byCourt[court.id];
                const idPrefix = `court-${court.id}`;
                return (
                  <li key={court.id} className={cn(grid, "rounded-lg", wide ? "px-2 py-2" : "border border-[#E5E1EF] p-3", wide && index % 2 === 1 && "bg-[#FBFAFE]")}>
                    {wide ? (
                      <span className="pt-3 text-sm font-medium">{index + 1}</span>
                    ) : (
                      <div className="col-span-full flex items-center justify-between">
                        <span className="flex h-6 w-6 items-center justify-center rounded-full bg-[#F1EBFF] text-xs font-semibold text-[#4817C2]">{index + 1}</span>
                        <button
                          type="button"
                          aria-label={`Remove ${court.name || `court ${index + 1}`}`}
                          onClick={() => onRemove(court.id)}
                          className="flex h-9 w-9 items-center justify-center rounded-lg text-[#C62828] hover:bg-[#FDECEA] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#C62828]"
                        >
                          <Trash2 className="h-4 w-4" aria-hidden="true" />
                        </button>
                      </div>
                    )}
                    <Cell label="Court Name" required className={wide ? undefined : "col-span-full"}>
                      <SetupInput
                        id={`${idPrefix}-name`}
                        aria-label={`Court ${index + 1} name`}
                        value={court.name}
                        maxLength={50}
                        invalid={!!p?.name}
                        onChange={(e) => onChange(court.id, { name: e.target.value })}
                      />
                      {p?.name && <FieldError>{p.name}</FieldError>}
                    </Cell>
                    {mode === "court" ? (
                      <SettingCells
                        idPrefix={idPrefix}
                        sportCode={active.code}
                        label={court.name || `Court ${index + 1}`}
                        settings={court}
                        problems={p}
                        onChange={(patch) => onChange(court.id, patch)}
                      />
                    ) : (
                      <p className={cn("flex items-center text-xs text-[#666666]", wide ? "col-span-4 h-11" : "col-span-full")}>Uses the settings for all {active.name} courts above.</p>
                    )}
                    {wide && (
                      <button
                        type="button"
                        aria-label={`Remove ${court.name || `court ${index + 1}`}`}
                        onClick={() => onRemove(court.id)}
                        className="flex h-11 w-8 items-center justify-center justify-self-end rounded-lg text-[#C62828] hover:bg-[#FDECEA] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#C62828]"
                      >
                        <Trash2 className="h-4 w-4" aria-hidden="true" />
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>

            {problems.bySport[active.id] && <FieldError>{problems.bySport[active.id]}</FieldError>}

            <button
              type="button"
              onClick={() => onAdd(active.id)}
              className="mt-3 flex h-10 items-center gap-1.5 rounded-lg border border-[#4817C2]/50 bg-[#F8F4FF] px-4 text-sm font-semibold text-[#4817C2] hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
            >
              <Plus className="h-4 w-4" aria-hidden="true" />
              Add Court
            </button>
          </div>
          </WideContext.Provider>
        </div>
      )}
    </SetupCard>
  );
}
