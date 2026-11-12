"use client";

import * as React from "react";
import { format } from "date-fns";
import { CalendarCheck, CalendarDays, Pencil, Plus, Trash2 } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { CardHeading, Field, SetupCard, SetupInput } from "@/features/onboarding/components/setup-fields";
import { setupFontClass } from "@/features/onboarding/components/onboarding-shell";
import { SetupCalendar } from "@/features/onboarding/components/setup-calendar";
import { closureProblem, formatClosureDate, sortClosures } from "@/features/operating-hours/setup-model";
import type { FacilityClosure } from "@/features/operating-hours/types";
import { cn } from "@/lib/utils";

const today = () => format(new Date(), "yyyy-MM-dd");

/** "Holiday / Special Closure": the dates the venue is closed, each with a name, plus an add / edit dialog. */
export function ClosuresCard({ closures, onChange }: { closures: FacilityClosure[]; onChange: (next: FacilityClosure[]) => void }) {
  // `target` is the closure being edited, or "new"
  const [target, setTarget] = React.useState<FacilityClosure | "new" | null>(null);
  const sorted = sortClosures(closures);

  function save(next: FacilityClosure) {
    if (target === "new" || target === null) onChange([...closures, next]);
    else onChange(closures.map((c) => (c === target ? next : c)));
    setTarget(null);
  }

  return (
    <SetupCard className="p-4 sm:p-5">
      <CardHeading
        icon={<CalendarCheck className="h-7 w-7" aria-hidden="true" />}
        title="Holiday / Special Closure"
        description="Mark dates when the facility will be closed (e.g., maintenance, events, public holidays)."
      />

      <ul className="space-y-2">
        {sorted.map((c) => (
          <li key={c.date} className="flex items-center gap-3 rounded-lg border border-[#EFECF6] bg-[#FBFAFE] px-3 py-2.5 text-sm">
            <CalendarDays className="h-5 w-5 shrink-0 text-[#4817C2]" aria-hidden="true" />
            <span className="font-medium">{formatClosureDate(c.date)}</span>
            <span className="min-w-0 truncate rounded-md bg-[#EDE7FF] px-2.5 py-0.5 text-xs font-semibold text-[#4817C2]">{c.name}</span>
            <span className="ml-auto flex shrink-0 gap-1">
              <button
                type="button"
                aria-label={`Edit ${c.name}`}
                onClick={() => setTarget(c)}
                className="flex h-8 w-8 items-center justify-center rounded-lg hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]"
              >
                <Pencil className="h-4 w-4" aria-hidden="true" />
              </button>
              <button
                type="button"
                aria-label={`Remove ${c.name}`}
                onClick={() => onChange(closures.filter((x) => x !== c))}
                className="flex h-8 w-8 items-center justify-center rounded-lg text-[#C62828] hover:bg-[#FDECEA] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#C62828]"
              >
                <Trash2 className="h-4 w-4" aria-hidden="true" />
              </button>
            </span>
          </li>
        ))}
      </ul>

      <button
        type="button"
        onClick={() => setTarget("new")}
        className={cn(
          "flex h-12 w-full items-center justify-center gap-2 rounded-lg border border-dashed border-[#4817C2]/60 bg-[#F8F4FF] text-sm font-semibold text-[#4817C2] hover:bg-[#F1EBFF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2]",
          sorted.length > 0 && "mt-3",
        )}
      >
        <Plus className="h-4 w-4" aria-hidden="true" />
        Add Holiday / Closure
      </button>

      {target !== null && (
        <ClosureDialog
          key={target === "new" ? "new" : target.date}
          existing={target === "new" ? null : target}
          others={closures}
          onSave={save}
          onClose={() => setTarget(null)}
        />
      )}
    </SetupCard>
  );
}

function ClosureDialog({ existing, others, onSave, onClose }: { existing: FacilityClosure | null; others: FacilityClosure[]; onSave: (c: FacilityClosure) => void; onClose: () => void }) {
  const [date, setDate] = React.useState(existing?.date ?? "");
  const [name, setName] = React.useState(existing?.name ?? "");
  const [problem, setProblem] = React.useState<string | null>(null);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const next = { date, name: name.trim() };
    const why = closureProblem(next, others, today(), existing);
    if (why) {
      setProblem(why);
      return;
    }
    onSave(next);
  }

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent className={cn(setupFontClass, "max-w-[340px] border-[#E5E1EF] bg-white text-[#171717] sm:max-w-[360px]")}>
        <form onSubmit={submit} noValidate className="space-y-4">
          <DialogHeader>
            <DialogTitle className="text-lg font-semibold">{existing ? "Edit Holiday / Closure" : "Add Holiday / Closure"}</DialogTitle>
            <DialogDescription className="text-sm text-[#666666]">Choose the date and give it a name.</DialogDescription>
          </DialogHeader>

          <Field id="closure-name" label="Name" required>
            <SetupInput
              id="closure-name"
              autoFocus
              value={name}
              maxLength={60}
              placeholder="e.g. Independence Day"
              invalid={!!problem && /name/i.test(problem)}
              onChange={(e) => {
                setName(e.target.value);
                setProblem(null);
              }}
            />
          </Field>

          <div>
            <p className="mb-1.5 text-sm font-semibold">
              Date <span className="text-[#C62828]">*</span>
            </p>
            <div className="flex justify-center rounded-xl border border-[#E5E1EF] p-2">
              <SetupCalendar
                value={date}
                min={today()}
                onSelect={(d) => {
                  setDate(d);
                  setProblem(null);
                }}
              />
            </div>
            <p className="mt-1.5 text-xs text-[#666666]" aria-live="polite">
              {date ? `Selected: ${formatClosureDate(date)}` : "Pick a date from the calendar."}
            </p>
          </div>

          {problem && (
            <p role="alert" className="text-xs font-medium text-[#C62828]">
              {problem}
            </p>
          )}

          <DialogFooter className="gap-2">
            <button type="button" onClick={onClose} className="h-11 rounded-lg border border-[#E5E1EF] bg-white px-5 text-sm font-semibold hover:bg-[#FBFAFE]">
              Cancel
            </button>
            <button type="submit" className="h-11 rounded-lg bg-[#4817C2] px-6 text-sm font-semibold text-white hover:bg-[#39109F]">
              {existing ? "Save" : "Add"}
            </button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
