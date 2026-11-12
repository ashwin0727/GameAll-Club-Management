import { describe, expect, it } from "vitest";
import {
  applyStandard,
  breakFitsDay,
  closureProblem,
  dailyMinutes,
  defaultPlans,
  describePlan,
  detectMode,
  formatClosureDate,
  formatHours,
  hasProblems,
  plansFromSchedule,
  scheduleFromPlans,
  sortClosures,
  validatePlans,
  weeklyMinutes,
  type DayPlan,
} from "@/features/operating-hours/setup-model";

const plan = (over: Partial<DayPlan> = {}): DayPlan => ({ dayOfWeek: 1, isOpen: true, open: "06:00", close: "23:00", is24Hours: false, ...over });

describe("a new venue's plan", () => {
  it("is open Monday to Saturday 6 AM - 11 PM and closed on Sunday", () => {
    const plans = defaultPlans();
    expect(plans.filter((p) => p.isOpen).map((p) => p.dayOfWeek)).toEqual([1, 2, 3, 4, 5, 6]);
    expect(plans.find((p) => p.dayOfWeek === 0)?.isOpen).toBe(false);
    expect(detectMode(plans)).toBe("standard");
  });
});

describe("plans <-> schedule", () => {
  it("one span per open day, and closed days carry no slots", () => {
    const days = scheduleFromPlans(defaultPlans());
    const mon = days.find((d) => d.dayOfWeek === 1)!;
    expect(mon).toMatchObject({ isClosed: false, is24Hours: false });
    expect(mon.slots).toEqual([{ startTime: "06:00", endTime: "23:00", crossesMidnight: false, displayOrder: 0 }]);
    expect(days.find((d) => d.dayOfWeek === 0)).toMatchObject({ isClosed: true, slots: [] });
  });

  it("a close at midnight or after crosses midnight", () => {
    const [mon] = scheduleFromPlans([plan({ open: "07:00", close: "00:00" })]).filter((d) => d.dayOfWeek === 1);
    expect(mon!.slots[0]).toMatchObject({ startTime: "07:00", endTime: "00:00", crossesMidnight: true });
  });

  it("a break splits the day into two slots, and reading it back folds it into one span again", () => {
    const brk = { start: "13:00", end: "14:00" };
    const days = scheduleFromPlans(defaultPlans(), brk);
    const mon = days.find((d) => d.dayOfWeek === 1)!;
    expect(mon.slots.map((s) => [s.startTime, s.endTime])).toEqual([["06:00", "13:00"], ["14:00", "23:00"]]);

    const back = plansFromSchedule(days, brk);
    expect(back.find((p) => p.dayOfWeek === 1)).toMatchObject({ isOpen: true, open: "06:00", close: "23:00" });
    expect(back.find((p) => p.dayOfWeek === 0)?.isOpen).toBe(false);
  });

  it("a break outside a day's hours leaves that day whole", () => {
    const days = scheduleFromPlans([plan({ open: "06:00", close: "12:00" })], { start: "13:00", end: "14:00" });
    expect(days.find((d) => d.dayOfWeek === 1)!.slots).toHaveLength(1);
  });

  it("24-hour days stay 24-hour", () => {
    const days = scheduleFromPlans([plan({ is24Hours: true })]);
    expect(days.find((d) => d.dayOfWeek === 1)).toMatchObject({ is24Hours: true, slots: [] });
    expect(plansFromSchedule(days).find((p) => p.dayOfWeek === 1)).toMatchObject({ isOpen: true, is24Hours: true });
  });

  it("an older day with no slots reads back as closed", () => {
    const back = plansFromSchedule([{ dayOfWeek: 2, isClosed: false, is24Hours: false, slots: [] }]);
    expect(back.find((p) => p.dayOfWeek === 2)?.isOpen).toBe(false);
  });
});

describe("standard or custom", () => {
  it("standard when every open day shares the same hours, custom otherwise", () => {
    expect(detectMode(applyStandard([1, 2, 3], "06:00", "22:00"))).toBe("standard");
    const mixed = applyStandard([1, 2, 3], "06:00", "22:00").map((p) => (p.dayOfWeek === 2 ? { ...p, close: "21:00" } : p));
    expect(detectMode(mixed)).toBe("custom");
  });

  it("applyStandard opens only the chosen days", () => {
    const plans = applyStandard([1, 6], "07:00", "20:00");
    expect(plans.filter((p) => p.isOpen).map((p) => p.dayOfWeek).sort()).toEqual([1, 6]);
    expect(plans.every((p) => p.open === "07:00" && p.close === "20:00")).toBe(true);
  });
});

describe("hours", () => {
  it("counts a day, overnight, with a break and as 24 hours", () => {
    expect(dailyMinutes(plan())).toBe(17 * 60);
    expect(dailyMinutes(plan({ open: "07:00", close: "00:00" }))).toBe(17 * 60);
    expect(dailyMinutes(plan(), { start: "13:00", end: "14:00" })).toBe(16 * 60);
    expect(dailyMinutes(plan({ is24Hours: true }))).toBe(1440);
    expect(dailyMinutes(plan({ isOpen: false }))).toBe(0);
  });

  it("adds up the whole week", () => {
    const week: DayPlan[] = [
      plan({ dayOfWeek: 1 }),
      plan({ dayOfWeek: 2 }),
      plan({ dayOfWeek: 3, close: "22:00" }),
      plan({ dayOfWeek: 4 }),
      plan({ dayOfWeek: 5 }),
      plan({ dayOfWeek: 6, open: "07:00", close: "00:00" }),
      plan({ dayOfWeek: 0, isOpen: false }),
    ];
    expect(weeklyMinutes(week)).toBe((17 + 17 + 16 + 17 + 17 + 17) * 60);
  });

  it("formats hours", () => {
    expect(formatHours(17 * 60)).toBe("17 Hours");
    expect(formatHours(60)).toBe("1 Hour");
    expect(formatHours(17.5 * 60)).toBe("17.5 Hours");
    expect(formatHours(0)).toBe("0 Hours");
  });

  it("describes a plan", () => {
    expect(describePlan(plan())).toBe("6:00 AM – 11:00 PM");
    expect(describePlan(plan({ open: "07:00", close: "00:00" }))).toBe("7:00 AM – 12:00 AM (next day)");
    expect(describePlan(plan({ isOpen: false }))).toBe("Closed");
    expect(describePlan(plan({ is24Hours: true }))).toBe("Open 24 hours");
  });
});

describe("validation", () => {
  it("needs at least one open day", () => {
    const r = validatePlans(applyStandard([], "06:00", "23:00"));
    expect(r.general).toBe("Select at least one operating day.");
    expect(hasProblems(r)).toBe(true);
  });

  it("opening and closing time cannot be the same", () => {
    const r = validatePlans([plan({ close: "06:00" })]);
    expect(r.byDay[1]).toBe("Opening and closing time cannot be the same.");
  });

  it("a valid week has no problems", () => {
    expect(hasProblems(validatePlans(defaultPlans()))).toBe(false);
  });

  it("the break must be a real range inside every open day's hours", () => {
    const plans = defaultPlans();
    expect(validatePlans(plans, { start: "13:00", end: "13:00" }).breakTime).toBe("The break's start and end time cannot be the same.");
    expect(validatePlans(plans, { start: "05:00", end: "07:00" }).breakTime).toBe("The break must fall inside the working hours of every open day.");
    expect(validatePlans(plans, { start: "22:00", end: "23:30" }).breakTime).toBeDefined();
    expect(validatePlans(plans, { start: "13:00", end: "14:00" }).breakTime).toBeUndefined();
  });

  it("breakFitsDay is strict about the edges", () => {
    expect(breakFitsDay({ open: "06:00", close: "23:00" }, { start: "06:00", end: "07:00" })).toBe(false);
    expect(breakFitsDay({ open: "06:00", close: "23:00" }, { start: "22:00", end: "23:00" })).toBe(false);
    expect(breakFitsDay({ open: "06:00", close: "23:00" }, { start: "12:00", end: "12:30" })).toBe(true);
    // an overnight day: 7 PM to 2 AM, break 11 PM to 11:30 PM
    expect(breakFitsDay({ open: "19:00", close: "02:00" }, { start: "23:00", end: "23:30" })).toBe(true);
  });
});

describe("closures", () => {
  const today = "2026-09-10";
  const ok = { date: "2026-12-25", name: "Christmas" };

  it("accepts a future date with a name", () => {
    expect(closureProblem(ok, [], today)).toBeNull();
    expect(closureProblem({ date: today, name: "Maintenance" }, [], today)).toBeNull();
  });

  it("needs a date, not in the past, and a name of 2-60 characters", () => {
    expect(closureProblem({ ...ok, date: "" }, [], today)).toBe("Select a date.");
    expect(closureProblem({ ...ok, date: "2026-09-01" }, [], today)).toBe("Choose today or a future date.");
    expect(closureProblem({ ...ok, name: " " }, [], today)).toBe("Enter a name of at least 2 characters.");
    expect(closureProblem({ ...ok, name: "x".repeat(61) }, [], today)).toBe("Keep the name under 60 characters.");
  });

  it("a date can be closed once", () => {
    expect(closureProblem(ok, [{ date: "2026-12-25", name: "Other" }], today)).toBe("This date is already marked as closed.");
  });

  it("editing a closure may keep its own (even past) date", () => {
    const existing = { date: "2026-08-15", name: "Independence Day" };
    expect(closureProblem({ date: "2026-08-15", name: "Independence Day!" }, [existing], today, existing)).toBeNull();
  });

  it("sorts earliest first and formats the date", () => {
    expect(sortClosures([{ date: "2027-01-01", name: "b" }, { date: "2026-08-15", name: "a" }]).map((c) => c.date)).toEqual(["2026-08-15", "2027-01-01"]);
    expect(formatClosureDate("2026-08-15")).toBe("15 Aug 2026 (Sat)");
    expect(formatClosureDate("2027-01-01")).toBe("01 Jan 2027 (Fri)");
  });
});
