import { DAYS_OF_WEEK, type DayOfWeek, type OperatingDay, type OperatingTimeSlot } from "@/features/operating-hours/types";

/**
 * day_of_week is stored 0=Sunday..6=Saturday (matches JS Date#getDay, useful
 * for the future Booking module) — but every example in the product spec
 * shows the week starting Monday, so the UI renders in this order instead.
 */
export const DISPLAY_ORDER: DayOfWeek[] = [1, 2, 3, 4, 5, 6, 0];

export const DEFAULT_OPEN_TIME = "06:00";
export const DEFAULT_CLOSE_TIME = "23:00";

const WEEKDAYS: DayOfWeek[] = [1, 2, 3, 4, 5];

function defaultSlot(): OperatingTimeSlot {
  return { startTime: DEFAULT_OPEN_TIME, endTime: DEFAULT_CLOSE_TIME, crossesMidnight: false, displayOrder: 0 };
}

export function buildDefaultDay(dayOfWeek: DayOfWeek): OperatingDay {
  return { dayOfWeek, isClosed: false, is24Hours: false, slots: [defaultSlot()] };
}

/** A fresh, all-open, default-hours week — the starting point when no schedule exists yet. */
export function buildDefaultWeek(): OperatingDay[] {
  return DAYS_OF_WEEK.map(buildDefaultDay);
}

export function build24HourDay(dayOfWeek: DayOfWeek): OperatingDay {
  return { dayOfWeek, isClosed: false, is24Hours: true, slots: [] };
}

export const QUICK_SETUP_PRESETS: { id: string; label: string; hint: string; build: () => OperatingDay[] }[] = [
  {
    id: "everyday",
    label: "Everyday",
    hint: "6:00 AM – 11:00 PM",
    build: () => DAYS_OF_WEEK.map((d) => buildDefaultDay(d)),
  },
  {
    id: "weekdays",
    label: "Weekdays",
    hint: "6:00 AM – 11:00 PM, closed weekends",
    build: () =>
      DAYS_OF_WEEK.map((d) =>
        WEEKDAYS.includes(d) ? buildDefaultDay(d) : { dayOfWeek: d, isClosed: true, is24Hours: false, slots: [] },
      ),
  },
  {
    id: "24-hours",
    label: "24 Hours",
    hint: "Every day",
    build: () => DAYS_OF_WEEK.map((d) => build24HourDay(d)),
  },
];