"use client";

import { BarChart3, BookOpen, Calendar, Users } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { money } from "@/features/coaching/components/shared";
import type { ProgramWizardFormState } from "@/features/coaching/components/use-program-wizard-form";

const PROGRAM_TYPE_LABEL: Record<string, string> = { GROUP: "Group Program", ONE_ON_ONE: "One-on-One", TRIAL: "Trial Program" };

/**
 * The wizard's right-side "live preview" — one shared component rendered on every step, reading
 * straight off the wizard's own state so it can never drift from what Create Program is about to
 * save (same reasoning the Add Member/Create Plan wizards' own preview panels already use).
 */
export function ProgramPreviewPanel({ form, sportName }: { form: ProgramWizardFormState; sportName: string | undefined }) {
  return (
    <div className="space-y-4">
      <Card className="overflow-hidden p-0">
        <div className="border-b border-border p-4">
          <h2 className="text-sm font-semibold">Program Preview</h2>
          <p className="text-xs text-muted-foreground">Here&apos;s a live preview based on the details you&apos;ve entered.</p>
        </div>
        <div className="p-4">
          <div className="flex gap-3">
            {form.imagePreview ? (
              // eslint-disable-next-line @next/next/no-img-element -- a live client-side object URL preview, not a served asset
              <img src={form.imagePreview} alt="" className="h-16 w-16 shrink-0 rounded-lg object-cover" />
            ) : (
              <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-lg bg-muted">
                <BookOpen className="h-6 w-6 text-muted-foreground" aria-hidden />
              </div>
            )}
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <p className="truncate font-semibold text-primary">{form.name.trim() || "Program Name"}</p>
                <Badge variant="outline" className="shrink-0 text-[10px]">
                  {PROGRAM_TYPE_LABEL[form.programType]}
                </Badge>
              </div>
              <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">
                {form.description.trim() || "Describe the program, what students will learn, and key highlights…"}
              </p>
            </div>
          </div>
          <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
            {sportName && <span>🏸 {sportName}</span>}
            <span>📊 {form.level}</span>
            <span>👥 Ages {form.ageGroup}</span>
          </div>
        </div>
      </Card>

      {(form.step === "Program Details" || form.step === "Schedule & Batches") && (
        <Card className="p-4">
          <h2 className="text-sm font-semibold">Program Summary</h2>
          <dl className="mt-3 space-y-2 text-sm">
            <Row icon={Users} label="Program Type" value={PROGRAM_TYPE_LABEL[form.programType]!} />
            <Row icon={BarChart3} label="Session Duration" value={`${form.effectiveSessionDuration} min`} />
            <Row icon={Calendar} label="Sessions per Week" value={String(form.sessionsPerWeek)} />
            <Row icon={Calendar} label="Start Date" value={fmt(form.startDate)} />
            <Row icon={Calendar} label="End Date" value={fmt(form.endDate)} />
            <Row icon={Users} label="Max Capacity" value={`${form.maxCapacity} Students`} />
            {form.minCapacity.trim() && <Row icon={Users} label="Minimum Students" value={`${form.minCapacity} Students`} />}
          </dl>
        </Card>
      )}

      {form.step === "Schedule & Batches" && (
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold">Batches Summary</h2>
            <span className="flex items-center gap-1 text-xs text-muted-foreground">
              <Users className="h-3.5 w-3.5" aria-hidden /> {form.batches.length} Batches
            </span>
          </div>
          {form.batches.length === 0 ? (
            <p className="mt-3 text-xs text-muted-foreground">No batches added yet.</p>
          ) : (
            <ul className="mt-3 space-y-2">
              {form.batches.map((b, i) => (
                <li key={i} className="rounded-lg border border-border p-2 text-xs">
                  <p className="font-medium">{b.name}</p>
                  <p className="text-muted-foreground">
                    {b.daysOfWeek.length} days · {b.startTime}–{b.endTime} · Capacity {b.capacity}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {form.step === "Pricing & Settings" && (
        <Card className="p-4">
          <h2 className="text-sm font-semibold">Fee Summary</h2>
          <dl className="mt-3 space-y-2 text-sm">
            {form.feeStructure === "PER_SESSION" ? (
              <>
                <Row label="Per Session Fee" value={money(form.priceInr * 100)} />
                <Row label="Total Sessions" value={String(form.totalSessionsInProgram)} />
                <div className="flex items-center justify-between border-t border-border pt-2">
                  <span className="text-muted-foreground">Subtotal</span>
                  <span className="font-medium">{money(form.perStudentBaseFeeInr * 100)}</span>
                </div>
              </>
            ) : (
              <Row label="Program Fee" value={money(form.priceInr * 100)} />
            )}
            {form.discountInr > 0 && <Row label="Early Bird Discount" value={`- ${money(form.discountInr * 100)}`} tone="text-success" />}
            <Row label={`Tax (GST ${form.taxApplicable ? form.taxPercent : 0}%)`} value={money(form.taxInr * 100)} />
            <div className="flex items-center justify-between border-t border-border pt-2 font-semibold">
              <span>Total Fee per Student</span>
              <span>{money(form.totalFeeInr * 100)}</span>
            </div>
          </dl>
        </Card>
      )}
    </div>
  );
}

function fmt(iso: string): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  return `${d} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][Number(m) - 1]} ${y}`;
}

function Row({ icon: Icon, label, value, tone }: { icon?: typeof Users; label: string; value: string; tone?: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="flex items-center gap-1.5 text-muted-foreground">
        {Icon && <Icon className="h-3.5 w-3.5" aria-hidden />}
        {label}
      </span>
      <span className={tone ?? "font-medium"}>{value}</span>
    </div>
  );
}
