import { Card } from "@/components/ui/card";
import { DISPLAY_ORDER } from "@/features/operating-hours/constants";
import { DAY_LABELS, type OperatingDay } from "@/features/operating-hours/types";

function formatTime12h(time: string): string {
  const [h, m] = time.split(":").map(Number);
  const hour = h ?? 0;
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  const meridiem = hour < 12 ? "AM" : "PM";
  return `${hour12}:${String(m ?? 0).padStart(2, "0")} ${meridiem}`;
}

function describeDay(day: OperatingDay): string {
  if (day.isClosed) return "Closed";
  if (day.is24Hours) return "Open 24 hours";
  if (day.slots.length === 0) return "Closed";
  return day.slots
    .map((slot) => `${formatTime12h(slot.startTime)} – ${formatTime12h(slot.endTime)}${slot.crossesMidnight ? " (next day)" : ""}`)
    .join(", ");
}

export function ScheduleSummary({
  days,
  playingAreaCount,
  customizedCount,
}: {
  days: OperatingDay[];
  playingAreaCount: number;
  customizedCount: number;
}) {
  const ordered = DISPLAY_ORDER.map((d) => days.find((day) => day.dayOfWeek === d)).filter(
    (d): d is OperatingDay => Boolean(d),
  );

  // Group consecutive days that describe identically, e.g. Monday–Friday.
  const groups: { label: string; description: string }[] = [];
  for (const day of ordered) {
    const description = describeDay(day);
    const last = groups[groups.length - 1];
    const dayLabel = DAY_LABELS[day.dayOfWeek];
    if (last && last.description === description && isConsecutive(last.label, dayLabel)) {
      const [start] = last.label.split(" – ");
      last.label = `${start} – ${dayLabel}`;
    } else {
      groups.push({ label: dayLabel, description });
    }
  }

  function isConsecutive(existingLabel: string, nextDayLabel: string): boolean {
    const lastDayInGroup = existingLabel.includes(" – ") ? existingLabel.split(" – ")[1] : existingLabel;
    const idx = DISPLAY_ORDER.findIndex((d) => DAY_LABELS[d] === lastDayInGroup);
    const nextIdx = DISPLAY_ORDER.findIndex((d) => DAY_LABELS[d] === nextDayLabel);
    return idx !== -1 && nextIdx === idx + 1;
  }

  return (
    <Card className="space-y-3 p-4 sm:p-5">
      <h3 className="text-sm font-semibold">Operating Hours</h3>
      <div className="space-y-1.5">
        {groups.map((group) => (
          <div key={group.label} className="flex flex-col text-sm sm:flex-row sm:items-baseline sm:gap-2">
            <span className="font-medium text-foreground">{group.label}</span>
            <span className="text-muted-foreground">{group.description}</span>
          </div>
        ))}
      </div>

      <div className="border-t border-border pt-3 text-sm">
        <p className="font-medium text-foreground">{playingAreaCount} Playing Areas</p>
        <p className="text-muted-foreground">
          {customizedCount === 0
            ? "All playing areas currently follow facility hours."
            : `${customizedCount} playing ${customizedCount === 1 ? "area has" : "areas have"} custom hours.`}
        </p>
      </div>
    </Card>
  );
}