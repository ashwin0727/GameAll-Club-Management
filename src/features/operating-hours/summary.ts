import { DISPLAY_ORDER } from "@/features/operating-hours/constants";
import { DAY_LABELS, type OperatingDay } from "@/features/operating-hours/types";

export function formatTime12h(time: string): string {
  const [h, m] = time.split(":").map(Number);
  const hour = h ?? 0;
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  const meridiem = hour < 12 ? "AM" : "PM";
  return `${hour12}:${String(m ?? 0).padStart(2, "0")} ${meridiem}`;
}

export function describeOperatingDay(day: OperatingDay): string {
  if (day.isClosed) return "Closed";
  if (day.is24Hours) return "Open 24 hours";
  if (day.slots.length === 0) return "Closed";
  return day.slots
    .map((slot) => `${formatTime12h(slot.startTime)} – ${formatTime12h(slot.endTime)}${slot.crossesMidnight ? " (next day)" : ""}`)
    .join(", ");
}

export interface OperatingHoursSummaryGroup {
  label: string;
  description: string;
}

/** Groups consecutive days (in display order) that describe identically, e.g. "Monday – Friday". */
export function groupOperatingDays(days: OperatingDay[]): OperatingHoursSummaryGroup[] {
  const ordered = DISPLAY_ORDER.map((d) => days.find((day) => day.dayOfWeek === d)).filter(
    (d): d is OperatingDay => Boolean(d),
  );

  function isConsecutive(existingLabel: string, nextDayLabel: string): boolean {
    const lastDayInGroup = existingLabel.includes(" – ") ? existingLabel.split(" – ")[1] : existingLabel;
    const idx = DISPLAY_ORDER.findIndex((d) => DAY_LABELS[d] === lastDayInGroup);
    const nextIdx = DISPLAY_ORDER.findIndex((d) => DAY_LABELS[d] === nextDayLabel);
    return idx !== -1 && nextIdx === idx + 1;
  }

  const groups: OperatingHoursSummaryGroup[] = [];
  for (const day of ordered) {
    const description = describeOperatingDay(day);
    const last = groups[groups.length - 1];
    const dayLabel = DAY_LABELS[day.dayOfWeek];
    if (last && last.description === description && isConsecutive(last.label, dayLabel)) {
      const [start] = last.label.split(" – ");
      last.label = `${start} – ${dayLabel}`;
    } else {
      groups.push({ label: dayLabel, description });
    }
  }
  return groups;
}